import logging

from django.db.models import Avg, Count
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import DeviceToken
from accounts.permissions import IsAdminVerified
from medunity.fcm import send_push_notification
from sos.models import haversine_km

from .models import ConsultantAvailability, ConsultantBooking, ConsultantReview

logger = logging.getLogger(__name__)


# ── helpers ───────────────────────────────────────────────────────────────────

def _prof_summary(prof, include_avg_rating=True) -> dict:
    d = {
        'id': prof.pk,
        'full_name': prof.full_name,
        'specialization': prof.get_specialization_display(),
        'specialization_key': prof.specialization,
        'years_experience': prof.years_experience,
        'qualification': prof.qualification,
        'about': prof.about,
        'profile_photo': prof.profile_photo.url if prof.profile_photo else None,
    }
    if include_avg_rating:
        agg = prof.reviews_received.aggregate(avg=Avg('rating'), count=Count('id'))
        d['avg_rating'] = round(agg['avg'], 1) if agg['avg'] else None
        d['review_count'] = agg['count']
    clinic = getattr(prof, 'clinic', None)
    if clinic:
        d['clinic_name'] = clinic.name
        d['clinic_city'] = clinic.city
    return d


def _booking_data(booking: ConsultantBooking, viewer_prof) -> dict:
    return {
        'id': booking.pk,
        'procedure': booking.procedure,
        'notes': booking.notes,
        'status': booking.status,
        'requested_at': booking.requested_at,
        'responded_at': booking.responded_at,
        'completed_at': booking.completed_at,
        'requester': _prof_summary(booking.requester, include_avg_rating=False),
        'consultant': _prof_summary(booking.consultant, include_avg_rating=True),
        'i_am_requester': booking.requester_id == viewer_prof.id,
        'my_review_submitted': booking.reviews.filter(reviewer=viewer_prof).exists(),
    }


# ── Availability toggle ───────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def my_availability(request):
    prof = request.user.professional
    avail, _ = ConsultantAvailability.objects.get_or_create(consultant=prof)

    if request.method == 'GET':
        return Response({
            'is_available': avail.is_available,
            'available_since': avail.available_since,
            'lat': float(avail.lat) if avail.lat else None,
            'lng': float(avail.lng) if avail.lng else None,
        })

    # POST — toggle
    make_available = request.data.get('is_available')
    if make_available is None:
        return Response({'detail': 'is_available required.'}, status=status.HTTP_400_BAD_REQUEST)

    if make_available:
        lat = request.data.get('lat')
        lng = request.data.get('lng')
        # Fall back to clinic lat/lng if not provided
        if lat is None:
            clinic = getattr(prof, 'clinic', None)
            lat = float(clinic.lat) if clinic and clinic.lat else None
            lng = float(clinic.lng) if clinic and clinic.lng else None
        avail.set_available(lat=lat, lng=lng)
    else:
        avail.set_unavailable()

    return Response({'is_available': avail.is_available})


# ── Nearby available consultants ──────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def nearby_consultants(request):
    prof = request.user.professional
    clinic = getattr(prof, 'clinic', None)

    if not clinic or clinic.lat is None:
        return Response(
            {'detail': 'Set your clinic location first.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        radius_km = float(request.query_params.get('radius_km', 10))
        radius_km = max(1.0, min(radius_km, 50.0))
    except (TypeError, ValueError):
        radius_km = 10.0

    specialization = request.query_params.get('specialization', '').strip()

    lat, lng = float(clinic.lat), float(clinic.lng)

    avails = ConsultantAvailability.objects.filter(
        is_available=True
    ).exclude(
        consultant=prof
    ).select_related('consultant__clinic', 'consultant')

    results = []
    for avail in avails:
        if avail.lat is None:
            continue
        dist = haversine_km(lat, lng, avail.lat, avail.lng)
        if dist > radius_km:
            continue
        c = avail.consultant
        if specialization and c.specialization != specialization:
            continue
        agg = c.reviews_received.aggregate(avg=Avg('rating'), count=Count('id'))
        row = _prof_summary(c)
        row['distance_km'] = round(dist, 2)
        row['available_since'] = avail.available_since
        results.append(row)

    results.sort(key=lambda x: x['distance_km'])
    return Response(results)


# ── Consultant public profile ─────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def consultant_profile(request, prof_id):
    from accounts.models import MedicalProfessional
    try:
        prof = MedicalProfessional.objects.get(pk=prof_id, is_admin_verified=True)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

    data = _prof_summary(prof)
    reviews = prof.reviews_received.select_related('reviewer').order_by('-created_at')[:10]
    data['recent_reviews'] = [
        {
            'rating': r.rating,
            'comment': r.comment,
            'reviewer_name': r.reviewer.full_name,
            'created_at': r.created_at,
        }
        for r in reviews
    ]
    avail = getattr(prof, 'availability', None)
    data['is_available'] = avail.is_available if avail else False
    return Response(data)


# ── Bookings ──────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def bookings(request):
    prof = request.user.professional

    if request.method == 'GET':
        role = request.query_params.get('role', 'all')
        if role == 'requester':
            qs = ConsultantBooking.objects.filter(requester=prof)
        elif role == 'consultant':
            qs = ConsultantBooking.objects.filter(consultant=prof)
        else:
            from django.db.models import Q
            qs = ConsultantBooking.objects.filter(Q(requester=prof) | Q(consultant=prof))

        qs = qs.select_related('requester__clinic', 'consultant__clinic').order_by('-requested_at')
        return Response([_booking_data(b, prof) for b in qs])

    # POST — request a consultant
    try:
        consultant_id = int(request.data['consultant_id'])
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'consultant_id required.'}, status=status.HTTP_400_BAD_REQUEST)

    procedure = request.data.get('procedure', '').strip()
    if not procedure:
        return Response({'detail': 'procedure is required.'}, status=status.HTTP_400_BAD_REQUEST)

    from accounts.models import MedicalProfessional
    try:
        consultant = MedicalProfessional.objects.get(pk=consultant_id, is_admin_verified=True)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Consultant not found.'}, status=status.HTTP_404_NOT_FOUND)

    if consultant.pk == prof.pk:
        return Response({'detail': 'Cannot book yourself.'}, status=status.HTTP_400_BAD_REQUEST)

    booking = ConsultantBooking.objects.create(
        requester=prof,
        consultant=consultant,
        procedure=procedure,
        notes=request.data.get('notes', '').strip(),
    )

    # Notify the consultant
    _push_booking_event(booking, 'new_booking',
                        f'New booking request from {prof.full_name}',
                        f'Procedure: {procedure}',
                        to=consultant)

    return Response(_booking_data(booking, prof), status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def booking_action(request, pk, action):
    prof = request.user.professional
    try:
        booking = ConsultantBooking.objects.select_related(
            'requester__clinic', 'consultant__clinic'
        ).get(pk=pk)
    except ConsultantBooking.DoesNotExist:
        return Response({'detail': 'Booking not found.'}, status=status.HTTP_404_NOT_FOUND)

    if action == 'accept':
        if booking.consultant_id != prof.id:
            return Response({'detail': 'Only the consultant can accept.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status != 'pending':
            return Response({'detail': f'Cannot accept a {booking.status} booking.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'accepted'
        booking.responded_at = timezone.now()
        booking.save(update_fields=['status', 'responded_at'])
        _push_booking_event(booking, 'booking_accepted',
                            '✅ Booking Accepted',
                            f'{prof.full_name} is on their way.',
                            to=booking.requester)

    elif action == 'decline':
        if booking.consultant_id != prof.id:
            return Response({'detail': 'Only the consultant can decline.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status != 'pending':
            return Response({'detail': f'Cannot decline a {booking.status} booking.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'declined'
        booking.responded_at = timezone.now()
        booking.save(update_fields=['status', 'responded_at'])
        _push_booking_event(booking, 'booking_declined',
                            'Booking Declined',
                            f'{prof.full_name} is unavailable.',
                            to=booking.requester)

    elif action == 'complete':
        if booking.consultant_id != prof.id and booking.requester_id != prof.id:
            return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status != 'accepted':
            return Response({'detail': 'Only accepted bookings can be completed.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'completed'
        booking.completed_at = timezone.now()
        booking.save(update_fields=['status', 'completed_at'])
        # Notify both sides to leave a review
        other = booking.requester if prof.pk == booking.consultant_id else booking.consultant
        _push_booking_event(booking, 'booking_completed',
                            '⭐ Rate your experience',
                            'The consultation is done. Leave a review.',
                            to=other)

    elif action == 'cancel':
        if booking.requester_id != prof.id:
            return Response({'detail': 'Only the requester can cancel.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status not in ('pending', 'accepted'):
            return Response({'detail': f'Cannot cancel a {booking.status} booking.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'cancelled'
        booking.save(update_fields=['status'])
        _push_booking_event(booking, 'booking_cancelled',
                            'Booking Cancelled',
                            f'{prof.full_name} cancelled the booking.',
                            to=booking.consultant)

    else:
        return Response({'detail': 'Unknown action.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(_booking_data(booking, prof))


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def submit_review(request, pk):
    prof = request.user.professional
    try:
        booking = ConsultantBooking.objects.get(pk=pk, status='completed')
    except ConsultantBooking.DoesNotExist:
        return Response({'detail': 'Completed booking not found.'}, status=status.HTTP_404_NOT_FOUND)

    if booking.requester_id != prof.id and booking.consultant_id != prof.id:
        return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)

    if booking.reviews.filter(reviewer=prof).exists():
        return Response({'detail': 'Already reviewed.'}, status=status.HTTP_409_CONFLICT)

    try:
        rating = int(request.data['rating'])
        if not (1 <= rating <= 5):
            raise ValueError
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'rating must be 1–5.'}, status=status.HTTP_400_BAD_REQUEST)

    reviewee = booking.consultant if booking.requester_id == prof.id else booking.requester
    ConsultantReview.objects.create(
        booking=booking,
        reviewer=prof,
        reviewee=reviewee,
        rating=rating,
        comment=request.data.get('comment', '').strip(),
    )
    return Response({'detail': 'Review submitted.'})


# ── FCM helper ────────────────────────────────────────────────────────────────

def _push_booking_event(booking, event_type, title, body, to):
    tokens = list(DeviceToken.objects.filter(user=to.user).values_list('token', flat=True))
    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title=title,
            body=body,
            data={
                'type': event_type,
                'booking_id': str(booking.pk),
                'deep_link': f'/consultants/bookings/{booking.pk}',
            },
            priority='high',
            channel_id='default',
        )
