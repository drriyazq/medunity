import logging
from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import DeviceToken
from accounts.permissions import IsAdminVerified
from medunity.fcm import send_push_notification

from .models import SosAlert, SosResponse, find_nearby_clinics, haversine_km

logger = logging.getLogger(__name__)

SOS_THROTTLE_MAX = 3
SOS_THROTTLE_WINDOW_HOURS = 24
# First 20 MedicalProfessional accounts are founding/test users — they bypass
# the 24h SOS throttle so they can stress-test the fan-out without hitting it.
SOS_THROTTLE_BYPASS_MAX_PROF_ID = 20


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def send_sos(request):
    prof = request.user.professional

    # Throttle: max 3 SOS per 24h, skipped for the first 20 accounts.
    if prof.id > SOS_THROTTLE_BYPASS_MAX_PROF_ID:
        cutoff = timezone.now() - timedelta(hours=SOS_THROTTLE_WINDOW_HOURS)
        recent_count = SosAlert.objects.filter(sender=prof, created_at__gte=cutoff).count()
        if recent_count >= SOS_THROTTLE_MAX:
            return Response(
                {'detail': 'SOS limit reached. You can send at most 3 SOS alerts per 24 hours.'},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

    category = request.data.get('category', '').strip()
    valid_categories = [c[0] for c in [
        ('medical_emergency', ''), ('legal_issue', ''),
        ('clinic_threat', ''), ('urgent_clinical', ''),
    ]]
    if category not in valid_categories:
        return Response({'detail': 'Invalid category.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        lat = float(request.data['lat'])
        lng = float(request.data['lng'])
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'lat and lng are required.'}, status=status.HTTP_400_BAD_REQUEST)

    # Find nearby clinics (auto-expand 1 → 2 → 5 km)
    clinics, radius_used = find_nearby_clinics(lat, lng, prof.id)

    # Optional: caller picks a subset of recipients (privacy control).
    # If recipient_ids omitted, fall back to broadcasting to all nearby (legacy).
    recipient_ids = request.data.get('recipient_ids')
    if recipient_ids is not None:
        if not isinstance(recipient_ids, list) or not recipient_ids:
            return Response(
                {'detail': 'Select at least one recipient.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            rid_set = {int(r) for r in recipient_ids}
        except (TypeError, ValueError):
            return Response(
                {'detail': 'recipient_ids must be integers.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        clinics = [c for c in clinics if c.owner_id in rid_set]
        if not clinics:
            return Response(
                {'detail': 'None of the selected recipients are in range.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

    alert = SosAlert.objects.create(
        sender=prof,
        category=category,
        lat=lat,
        lng=lng,
        radius_km=radius_used,
        recipient_count=len(clinics),
    )

    # FCM push to all recipients
    category_labels = {
        'medical_emergency': 'Medical Emergency',
        'legal_issue': 'Legal Issue',
        'clinic_threat': 'Clinic Under Threat',
        'urgent_clinical': 'Urgent Clinical Assistance',
    }
    category_display = category_labels.get(category, category)
    sender_name = prof.full_name or 'A nearby doctor'

    pushed = 0
    for clinic in clinics:
        tokens = list(
            DeviceToken.objects.filter(user=clinic.owner.user).values_list('token', flat=True)
        )
        for token in tokens:
            ok = send_push_notification(
                fcm_token=token,
                title=f'🆘 SOS — {category_display}',
                body=f'{sender_name} needs help nearby. Tap to respond.',
                data={
                    'type': 'sos_alert',
                    'alert_id': str(alert.pk),
                    'category': category,
                    'category_display': category_display,
                    'deep_link': f'/sos/incoming/{alert.pk}',
                },
                priority='high',
                channel_id='sos_critical',
                sound='siren',
            )
            if ok:
                pushed += 1

    logger.info(f'[SOS] Alert #{alert.pk} sent to {len(clinics)} clinics ({pushed} tokens), radius={radius_used}km')

    return Response({
        'alert_id': alert.pk,
        'radius_km': radius_used,
        'recipient_count': len(clinics),
    }, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def nearby_doctors(request):
    """List doctors within auto-expand radius for the SOS recipient picker.

    Lets the sender choose who receives their SOS instead of broadcasting
    to every nearby doctor (privacy control).
    """
    prof = request.user.professional
    try:
        lat = float(request.query_params['lat'])
        lng = float(request.query_params['lng'])
    except (KeyError, TypeError, ValueError):
        return Response(
            {'detail': 'lat and lng query params required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    clinics, radius_km = find_nearby_clinics(lat, lng, prof.id)
    doctors = []
    for c in clinics:
        owner = c.owner
        try:
            spec = owner.get_specialization_display()
        except Exception:
            spec = ''
        doctors.append({
            'professional_id': owner.id,
            'full_name': owner.full_name,
            'specialization_display': spec,
            'clinic_name': c.name,
            'clinic_city': c.city,
            'distance_km': round(haversine_km(lat, lng, c.lat, c.lng), 2),
        })
    doctors.sort(key=lambda d: d['distance_km'])
    return Response({'doctors': doctors, 'radius_km': radius_km})


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def respond_to_sos(request, pk):
    prof = request.user.professional

    try:
        alert = SosAlert.objects.get(pk=pk)
    except SosAlert.DoesNotExist:
        return Response({'detail': 'SOS alert not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not alert.is_active:
        return Response({'detail': 'This SOS alert is no longer active.'}, status=status.HTTP_410_GONE)

    if alert.sender_id == prof.id:
        return Response({'detail': 'Cannot respond to your own SOS.'}, status=status.HTTP_400_BAD_REQUEST)

    response_status = request.data.get('status', '').strip()
    if response_status not in ('accepted', 'declined'):
        return Response({'detail': 'status must be "accepted" or "declined".'}, status=status.HTTP_400_BAD_REQUEST)

    responder_lat = request.data.get('lat')
    responder_lng = request.data.get('lng')

    sos_response, created = SosResponse.objects.update_or_create(
        alert=alert,
        responder=prof,
        defaults={
            'status': response_status,
            'responder_lat': responder_lat,
            'responder_lng': responder_lng,
        },
    )

    # Notify the sender if accepted
    if response_status == 'accepted':
        sender_tokens = list(
            DeviceToken.objects.filter(user=alert.sender.user).values_list('token', flat=True)
        )
        for token in sender_tokens:
            send_push_notification(
                fcm_token=token,
                title='✅ Someone is on their way',
                body=f'{prof.full_name} accepted your SOS and is coming.',
                data={
                    'type': 'sos_response',
                    'alert_id': str(alert.pk),
                    'deep_link': f'/sos/status/{alert.pk}',
                },
                priority='high',
                channel_id='sos_critical',
            )

    return Response({'detail': 'Response recorded.', 'created': created})


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def sos_status(request, pk):
    """
    Returns accepted responder details for the alert sender.
    Names + clinic are included because a responder accepting to physically
    come help is implicitly de-anonymising themselves to the sender.
    """
    try:
        alert = SosAlert.objects.get(pk=pk)
    except SosAlert.DoesNotExist:
        return Response({'detail': 'SOS alert not found.'}, status=status.HTTP_404_NOT_FOUND)

    prof = request.user.professional
    if alert.sender_id != prof.id:
        return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)

    accepted = (
        alert.responses.filter(status='accepted')
        .select_related('responder__user', 'responder__clinic')
        .order_by('responded_at')
    )
    sender_lat, sender_lng = float(alert.lat), float(alert.lng)

    responders = []
    dots = []
    for r in accepted:
        responder = r.responder
        clinic = getattr(responder, 'clinic', None)
        r_lat = float(r.responder_lat) if r.responder_lat is not None else None
        r_lng = float(r.responder_lng) if r.responder_lng is not None else None
        distance_km = None
        if r_lat is not None and r_lng is not None:
            distance_km = round(haversine_km(sender_lat, sender_lng, r_lat, r_lng), 2)
            dots.append({'lat': r_lat, 'lng': r_lng})
        responders.append({
            'response_id': r.pk,
            'professional_id': responder.id,
            'full_name': responder.full_name,
            'specialization_display': responder.get_specialization_display(),
            'phone': responder.phone,
            'clinic_name': clinic.name if clinic else '',
            'clinic_address': clinic.address if clinic else '',
            'lat': r_lat,
            'lng': r_lng,
            'distance_km': distance_km,
            'accepted_at': r.responded_at,
        })

    return Response({
        'alert_id': alert.pk,
        'status': alert.status,
        'is_active': alert.is_active,
        'category': alert.category,
        'category_display': alert.get_category_display(),
        'accepted_count': len(responders),
        'recipient_count': alert.recipient_count,
        'responders': responders,
        'responder_dots': dots,  # kept for backward compat with older app builds
        'sender_lat': sender_lat,
        'sender_lng': sender_lng,
        'created_at': alert.created_at,
        'expires_at': alert.expires_at,
    })


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def my_alerts(request):
    """List the authenticated sender's SOS alerts (newest first, last 30 days)."""
    prof = request.user.professional
    cutoff = timezone.now() - timedelta(days=30)
    alerts = (
        SosAlert.objects
        .filter(sender=prof, created_at__gte=cutoff)
        .prefetch_related('responses')
        .order_by('-created_at')
    )
    items = []
    for a in alerts:
        accepted_count = sum(1 for r in a.responses.all() if r.status == 'accepted')
        items.append({
            'alert_id': a.pk,
            'category': a.category,
            'category_display': a.get_category_display(),
            'is_active': a.is_active,
            'status': a.status,
            'recipient_count': a.recipient_count,
            'accepted_count': accepted_count,
            'radius_km': a.radius_km,
            'lat': float(a.lat),
            'lng': float(a.lng),
            'created_at': a.created_at,
            'expires_at': a.expires_at,
        })
    return Response({'alerts': items})


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def incoming_sos(request, pk):
    """Returns a single incoming SOS alert detail for the recipient."""
    try:
        alert = SosAlert.objects.get(pk=pk)
    except SosAlert.DoesNotExist:
        return Response({'detail': 'SOS alert not found.'}, status=status.HTTP_404_NOT_FOUND)

    prof = request.user.professional
    existing_response = SosResponse.objects.filter(alert=alert, responder=prof).first()

    return Response({
        'alert_id': alert.pk,
        'category': alert.category,
        'category_display': alert.get_category_display(),
        'is_active': alert.is_active,
        'sender_lat': float(alert.lat),
        'sender_lng': float(alert.lng),
        'created_at': alert.created_at,
        'my_response': existing_response.status if existing_response else None,
    })
