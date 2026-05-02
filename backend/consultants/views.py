import logging

from django.core.cache import cache
from django.db.models import Avg, Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import DeviceToken, MedicalProfessional
from accounts.permissions import IsAdminVerified
from medunity.fcm import send_push_notification
from sos.models import haversine_km

from .models import (
    ConsultantAllowlist,
    ConsultantAvailability,
    ConsultantBlocklist,
    ConsultantBooking,
    ConsultantReview,
)
from .schedule import is_within_schedule, validate_schedule
from .specialty_map import ALL as SPECIALTY_ALL
from .specialty_map import searchable_specialties

logger = logging.getLogger(__name__)


# ── Live-location constants ───────────────────────────────────────────────────

SEARCH_CACHE_TTL_SECONDS = 15 * 60  # Triangulation defense — 15-min refresh cap
DISTANCE_BUCKETS = (
    (2.0, 'Within 2 km'),
    (5.0, '2–5 km'),
    (10.0, '5–10 km'),
)


def _bucket_distance(km: float) -> str:
    for limit, label in DISTANCE_BUCKETS:
        if km <= limit:
            return label
    return f'Within {int(round(km))} km'


# ── helpers ───────────────────────────────────────────────────────────────────

def _prof_summary(prof, include_avg_rating=True, include_phone=False) -> dict:
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
    if include_phone:
        d['phone'] = prof.phone or ''
    clinic = getattr(prof, 'clinic', None)
    if clinic:
        d['clinic_name'] = clinic.name
        d['clinic_city'] = clinic.city
    return d


def _booking_data(booking: ConsultantBooking, viewer_prof) -> dict:
    """Phone visibility rules:
    - Requester's phone is always visible to the consultant (so they can call
      the requesting doctor before deciding to accept).
    - Consultant's phone is visible to the requester only after the consultant
      has accepted (or completed) — symmetric reveal.
    """
    viewer_is_requester = booking.requester_id == viewer_prof.id
    viewer_is_consultant = booking.consultant_id == viewer_prof.id
    consultant_phone_visible = booking.status in ('accepted', 'completed')

    return {
        'id': booking.pk,
        'procedure': booking.procedure,
        'notes': booking.notes,
        'status': booking.status,
        'requested_at': booking.requested_at,
        'responded_at': booking.responded_at,
        'completed_at': booking.completed_at,
        'requester': _prof_summary(
            booking.requester,
            include_avg_rating=False,
            include_phone=viewer_is_consultant,
        ),
        'consultant': _prof_summary(
            booking.consultant,
            include_avg_rating=True,
            include_phone=viewer_is_requester and consultant_phone_visible,
        ),
        'i_am_requester': viewer_is_requester,
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

def _consultant_card(prof, distance_label: str) -> dict:
    """Privacy-safe public card — no exact distance, no last-seen."""
    return {
        'id': prof.pk,
        'full_name': prof.full_name,
        'specialization': prof.get_specialization_display(),
        'specialization_key': prof.specialization,
        'distance_label': distance_label,
        'available_label': 'Available now',
        'profile_photo': prof.profile_photo.url if prof.profile_photo else None,
        'avg_rating': None,  # filled below
        'review_count': 0,
    }


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

    lat, lng = float(clinic.lat), float(clinic.lng)
    sort = request.query_params.get('sort', 'distance').strip()
    if sort not in ('distance', 'rating'):
        sort = 'distance'
    # Bucketed cache key — 0.01° ≈ 1.1 km — keeps the 15-min cache stable while
    # the doctor walks around their clinic without forcing recomputes. Sort is
    # in the key so changing it doesn't return a wrong-sort cached payload.
    cache_key = (
        f'consult_search:{prof.pk}:{round(lat, 2)}:{round(lng, 2)}'
        f':{prof.specialization}:{",".join(sorted(prof.roles or []))}'
        f':sort={sort}'
    )
    cached = cache.get(cache_key)
    if cached is not None:
        return Response(cached)

    allowed_specialties = searchable_specialties(prof.specialization, prof.roles or [])

    avails = ConsultantAvailability.objects.filter(
        is_available=True
    ).exclude(
        consultant=prof
    ).select_related('consultant__clinic', 'consultant')

    results = []
    for avail in avails:
        if avail.lat is None:
            continue
        c = avail.consultant
        # Specialty filter
        if allowed_specialties is not SPECIALTY_ALL and c.specialization not in allowed_specialties:
            continue
        dist = haversine_km(lat, lng, avail.lat, avail.lng)
        # Per-consultant radius — they decide how far doctors can find them
        if dist > avail.travel_radius_km:
            continue
        # Visibility mode
        if avail.visibility_mode == 'allowlist':
            if not ConsultantAllowlist.objects.filter(
                consultant=c, doctor=prof
            ).exists():
                continue
        else:  # 'open'
            if ConsultantBlocklist.objects.filter(
                consultant=c, doctor=prof
            ).exists():
                continue
        agg = c.reviews_received.aggregate(avg=Avg('rating'), count=Count('id'))
        card = _consultant_card(c, _bucket_distance(dist))
        card['avg_rating'] = round(agg['avg'], 1) if agg['avg'] else None
        card['review_count'] = agg['count']
        # Internal sort key — not returned
        card['_sort'] = dist
        results.append(card)

    if sort == 'rating':
        # Highest avg first; null ratings sink to the bottom; ties broken by
        # distance so the closest equally-rated consultant wins.
        results.sort(key=lambda r: (
            -(r['avg_rating'] or 0),
            -(r['review_count'] or 0),
            r['_sort'],
        ))
    else:
        results.sort(key=lambda r: r['_sort'])
    for r in results:
        r.pop('_sort', None)

    cache.set(cache_key, results, SEARCH_CACHE_TTL_SECONDS)
    return Response(results)


# ── Live-location ping ────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAdminVerified])
def update_location(request):
    """Periodic location update from the foreground service.

    Body: {lat, lng}. Rejects (409) if the consultant is not currently `is_available`
    so a backgrounded service can't keep pushing after the user toggled off.
    """
    prof = request.user.professional
    avail, _ = ConsultantAvailability.objects.get_or_create(consultant=prof)
    if not avail.is_available:
        return Response(
            {'detail': 'Not live. Toggle Go Live before sending location.'},
            status=status.HTTP_409_CONFLICT,
        )
    try:
        lat = float(request.data['lat'])
        lng = float(request.data['lng'])
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'lat and lng required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    avail.lat = lat
    avail.lng = lng
    avail.last_ping_at = timezone.now()
    avail.save(update_fields=['lat', 'lng', 'last_ping_at', 'updated_at'])
    return Response({'ok': True})


# ── Settings (mobility, schedule, radius, visibility mode) ────────────────────

def _settings_payload(avail: ConsultantAvailability) -> dict:
    return {
        'is_available': avail.is_available,
        'mobility_mode': avail.mobility_mode,
        'travel_radius_km': avail.travel_radius_km,
        'working_schedule': avail.working_schedule or [],
        'visibility_mode': avail.visibility_mode,
        'within_scheduled_window': is_within_schedule(avail.working_schedule or []),
    }


@api_view(['GET', 'PATCH'])
@permission_classes([IsAdminVerified])
def my_settings(request):
    prof = request.user.professional
    avail, _ = ConsultantAvailability.objects.get_or_create(consultant=prof)

    if request.method == 'GET':
        return Response(_settings_payload(avail))

    data = request.data
    update_fields = []
    if 'mobility_mode' in data:
        if data['mobility_mode'] not in ('mobile', 'stationary'):
            return Response({'detail': 'Invalid mobility_mode.'},
                            status=status.HTTP_400_BAD_REQUEST)
        avail.mobility_mode = data['mobility_mode']
        update_fields.append('mobility_mode')
    if 'travel_radius_km' in data:
        try:
            r = int(data['travel_radius_km'])
            if not (1 <= r <= 50):
                raise ValueError
        except (TypeError, ValueError):
            return Response({'detail': 'travel_radius_km must be 1–50.'},
                            status=status.HTTP_400_BAD_REQUEST)
        avail.travel_radius_km = r
        update_fields.append('travel_radius_km')
    if 'working_schedule' in data:
        try:
            avail.working_schedule = validate_schedule(data['working_schedule'])
        except ValueError as e:
            return Response({'detail': str(e)},
                            status=status.HTTP_400_BAD_REQUEST)
        update_fields.append('working_schedule')
    if 'visibility_mode' in data:
        if data['visibility_mode'] not in ('open', 'allowlist'):
            return Response({'detail': 'Invalid visibility_mode.'},
                            status=status.HTTP_400_BAD_REQUEST)
        avail.visibility_mode = data['visibility_mode']
        update_fields.append('visibility_mode')

    if update_fields:
        update_fields.append('updated_at')
        avail.save(update_fields=update_fields)
    return Response(_settings_payload(avail))


# ── Blocklist + Allowlist ─────────────────────────────────────────────────────

def _doctor_card(prof: MedicalProfessional) -> dict:
    return {
        'id': prof.pk,
        'full_name': prof.full_name,
        'specialization': prof.get_specialization_display(),
        'phone': prof.phone or '',
        'profile_photo': prof.profile_photo.url if prof.profile_photo else None,
    }


def _list_view(model, request, label: str):
    """Shared GET/POST/DELETE handler for blocklist + allowlist."""
    me = request.user.professional

    if request.method == 'GET':
        qs = model.objects.filter(consultant=me).select_related('doctor')
        return Response([_doctor_card(r.doctor) for r in qs])

    # Resolve target doctor — by id or phone
    doctor_id = request.data.get('doctor_id')
    phone = (request.data.get('phone') or '').strip()
    target = None
    if doctor_id:
        target = MedicalProfessional.objects.filter(
            pk=doctor_id, is_admin_verified=True
        ).first()
    elif phone:
        # Normalise phone — strip spaces / + / dashes; backends store with leading +
        cleaned = phone.replace(' ', '').replace('-', '')
        if not cleaned.startswith('+') and len(cleaned) == 10:
            cleaned = '+91' + cleaned
        elif not cleaned.startswith('+'):
            cleaned = '+' + cleaned
        target = MedicalProfessional.objects.filter(
            phone=cleaned, is_admin_verified=True
        ).first()

    if not target:
        return Response({'detail': f'Doctor not found for {label}.'},
                        status=status.HTTP_404_NOT_FOUND)
    if target.pk == me.pk:
        return Response({'detail': 'Cannot add yourself.'},
                        status=status.HTTP_400_BAD_REQUEST)

    if request.method == 'POST':
        obj, created = model.objects.get_or_create(consultant=me, doctor=target)
        # Adding to one list removes from the other (mutual exclusion)
        opposite = ConsultantBlocklist if model is ConsultantAllowlist else ConsultantAllowlist
        opposite.objects.filter(consultant=me, doctor=target).delete()
        # Bust the doctor's search cache — they should see the change quickly
        cache.delete_many(_search_cache_keys_for_doctor(target.pk))
        return Response({'added': created, 'doctor': _doctor_card(target)},
                        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)

    # DELETE
    deleted, _ = model.objects.filter(consultant=me, doctor=target).delete()
    cache.delete_many(_search_cache_keys_for_doctor(target.pk))
    return Response({'removed': bool(deleted), 'doctor': _doctor_card(target)})


def _search_cache_keys_for_doctor(_doctor_id: int) -> list:
    """Return cache keys to bust when a doctor's visibility might change.

    The cache keys are bucketed on (lat, lng, specialization, roles) so we can't
    construct them precisely without the doctor's clinic. For now return an empty
    list — cache TTL (15 min) bounds the staleness. Future improvement: store a
    secondary index of cache keys per doctor.
    """
    return []


@api_view(['GET', 'POST', 'DELETE'])
@permission_classes([IsAdminVerified])
def my_blocklist(request):
    return _list_view(ConsultantBlocklist, request, 'blocklist')


@api_view(['GET', 'POST', 'DELETE'])
@permission_classes([IsAdminVerified])
def my_allowlist(request):
    return _list_view(ConsultantAllowlist, request, 'allowlist')


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def lookup_by_phone(request):
    """For the allowlist UI — find a doctor by phone before adding."""
    phone = (request.query_params.get('phone') or '').strip()
    if not phone:
        return Response({'detail': 'phone required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    cleaned = phone.replace(' ', '').replace('-', '')
    if not cleaned.startswith('+') and len(cleaned) == 10:
        cleaned = '+91' + cleaned
    elif not cleaned.startswith('+'):
        cleaned = '+' + cleaned
    target = MedicalProfessional.objects.filter(
        phone=cleaned, is_admin_verified=True
    ).first()
    if not target or target.pk == request.user.professional.pk:
        return Response({'detail': 'No verified doctor with that number.'},
                        status=status.HTTP_404_NOT_FOUND)
    return Response(_doctor_card(target))


# ── Decline + Block (extends booking_action) ─────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAdminVerified])
def decline_and_block(request, pk):
    """Consultant rejects an incoming booking AND blocks the requester."""
    prof = request.user.professional
    try:
        booking = ConsultantBooking.objects.get(pk=pk)
    except ConsultantBooking.DoesNotExist:
        return Response({'detail': 'Booking not found.'},
                        status=status.HTTP_404_NOT_FOUND)
    if booking.consultant_id != prof.id:
        return Response({'detail': 'Forbidden.'},
                        status=status.HTTP_403_FORBIDDEN)
    if booking.status != 'pending':
        return Response({'detail': f'Cannot decline a {booking.status} booking.'},
                        status=status.HTTP_409_CONFLICT)
    booking.status = 'declined'
    booking.responded_at = timezone.now()
    booking.save(update_fields=['status', 'responded_at'])
    ConsultantBlocklist.objects.get_or_create(
        consultant=prof, doctor=booking.requester,
        defaults={'reason': 'Declined incoming booking'},
    )
    _push_booking_event(booking, 'booking_declined',
                        'Booking Declined',
                        f'{prof.full_name} is unavailable.',
                        to=booking.requester)
    return Response(_booking_data(booking, prof))


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

    # Notify the consultant — they need the requester's phone immediately
    # so they can call before deciding to accept.
    body = f'Procedure: {procedure}'
    if prof.phone:
        body += f'\n📞 Call requester: {prof.phone}'
    _push_booking_event(booking, 'new_booking', body=body,
                        title=f'New booking request from {prof.full_name}',
                        to=consultant, recipient_role='consultant')

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
        # Reveal consultant's phone in the body so the requester can call them.
        body = f'{prof.full_name} is on their way.'
        if prof.phone:
            body += f'\n📞 {prof.phone}'
        _push_booking_event(booking, 'booking_accepted',
                            title='✅ Booking Accepted', body=body,
                            to=booking.requester, recipient_role='requester')

    elif action == 'decline':
        if booking.consultant_id != prof.id:
            return Response({'detail': 'Only the consultant can decline.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status != 'pending':
            return Response({'detail': f'Cannot decline a {booking.status} booking.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'declined'
        booking.responded_at = timezone.now()
        booking.save(update_fields=['status', 'responded_at'])
        _push_booking_event(booking, 'booking_declined',
                            title='Booking Declined',
                            body=f'{prof.full_name} is unavailable.',
                            to=booking.requester, recipient_role='requester')

    elif action == 'complete':
        if booking.consultant_id != prof.id and booking.requester_id != prof.id:
            return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status != 'accepted':
            return Response({'detail': 'Only accepted bookings can be completed.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'completed'
        booking.completed_at = timezone.now()
        booking.save(update_fields=['status', 'completed_at'])
        # Notify the other side to leave a review.
        other = booking.requester if prof.pk == booking.consultant_id else booking.consultant
        other_role = 'requester' if other.pk == booking.requester_id else 'consultant'
        _push_booking_event(booking, 'booking_completed',
                            title='⭐ Rate your experience',
                            body='The consultation is done. Leave a review.',
                            to=other, recipient_role=other_role)

    elif action == 'cancel':
        if booking.requester_id != prof.id:
            return Response({'detail': 'Only the requester can cancel.'}, status=status.HTTP_403_FORBIDDEN)
        if booking.status not in ('pending', 'accepted'):
            return Response({'detail': f'Cannot cancel a {booking.status} booking.'}, status=status.HTTP_409_CONFLICT)
        booking.status = 'cancelled'
        booking.save(update_fields=['status'])
        _push_booking_event(booking, 'booking_cancelled',
                            title='Booking Cancelled',
                            body=f'{prof.full_name} cancelled the booking.',
                            to=booking.consultant, recipient_role='consultant')

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

def _push_booking_event(booking, event_type, title, body, to, recipient_role='consultant'):
    """recipient_role: 'consultant' or 'requester' — drives the deep-link query
    param so the Flutter app opens the right Bookings sub-tab on tap."""
    tokens = list(DeviceToken.objects.filter(user=to.user).values_list('token', flat=True))
    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title=title,
            body=body,
            data={
                'type': event_type,
                'booking_id': str(booking.pk),
                'recipient_role': recipient_role,
                'deep_link': f'/consultants/bookings/{booking.pk}?as={recipient_role}',
            },
            priority='high',
            channel_id='consultant_request_v1',
            sound='consult_chime',
        )
