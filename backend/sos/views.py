import logging
from datetime import timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import DeviceToken
from accounts.permissions import IsAdminVerified
from medunity.fcm import send_push_notification

from .models import SosAlert, SosResponse, find_nearby_clinics

logger = logging.getLogger(__name__)

SOS_THROTTLE_MAX = 3
SOS_THROTTLE_WINDOW_HOURS = 24


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def send_sos(request):
    prof = request.user.professional

    # Throttle: max 3 SOS per 24h
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
    Returns accepted response count + list of {lat, lng} map dots only.
    No names, no IDs of responders.
    """
    try:
        alert = SosAlert.objects.get(pk=pk)
    except SosAlert.DoesNotExist:
        return Response({'detail': 'SOS alert not found.'}, status=status.HTTP_404_NOT_FOUND)

    prof = request.user.professional
    if alert.sender_id != prof.id:
        return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)

    accepted = alert.responses.filter(status='accepted')
    dots = [
        {'lat': float(r.responder_lat), 'lng': float(r.responder_lng)}
        for r in accepted
        if r.responder_lat is not None and r.responder_lng is not None
    ]

    return Response({
        'alert_id': alert.pk,
        'status': alert.status,
        'is_active': alert.is_active,
        'category': alert.category,
        'category_display': alert.get_category_display(),
        'accepted_count': accepted.count(),
        'responder_dots': dots,
        'expires_at': alert.expires_at,
    })


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
