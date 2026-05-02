"""Endpoints for the associate-doctor marketplace + global doctor reviews.

All endpoints require IsAdminVerified (any verified MedicalProfessional
can use them — both as hiring clinic and as associate).
"""
import math
from decimal import Decimal

from django.db.models import Avg, Count, Q
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.models import MedicalProfessional
from accounts.permissions import IsAdminVerified
from medunity.fcm import send_push_notification

from .models import AssociateBooking, AssociateProfile, ProfessionalReview
from .serializers import (
    AssociateBookingSerializer,
    AssociateProfileSerializer,
    ProfessionalReviewSerializer,
)


# ── helpers ──────────────────────────────────────────────────────────────────

def _haversine_km(lat1, lng1, lat2, lng2) -> float:
    R = 6371.0
    dlat = math.radians(float(lat2) - float(lat1))
    dlng = math.radians(float(lng2) - float(lng1))
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(float(lat1)))
         * math.cos(math.radians(float(lat2)))
         * math.sin(dlng / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def _aggregate_rating(prof_id, context=None):
    qs = ProfessionalReview.objects.filter(reviewee_id=prof_id)
    if context:
        qs = qs.filter(context=context)
    agg = qs.aggregate(avg=Avg('rating'), n=Count('id'))
    return {
        'avg_rating': float(agg['avg']) if agg['avg'] is not None else None,
        'review_count': agg['n'] or 0,
    }


def _push_to_user(user, title, body, data, channel='general'):
    from accounts.models import DeviceToken
    tokens = list(DeviceToken.objects.filter(user=user).values_list('token', flat=True))
    for t in tokens:
        send_push_notification(
            fcm_token=t, title=title, body=body, data=data,
            priority='high', channel_id=channel,
        )


# ── /me/ — own associate profile ─────────────────────────────────────────────

@api_view(['GET', 'PATCH'])
@permission_classes([IsAdminVerified])
def me_associate_profile(request):
    prof = request.user.professional
    profile, _ = AssociateProfile.objects.get_or_create(professional=prof)

    if request.method == 'GET':
        return Response(AssociateProfileSerializer(profile).data)

    serializer = AssociateProfileSerializer(profile, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    _fallback_base_location_from_clinic(profile, prof)
    return Response(AssociateProfileSerializer(profile).data)


def _fallback_base_location_from_clinic(profile, prof):
    if profile.base_lat is not None and profile.base_lng is not None:
        return
    clinic = getattr(prof, 'clinic', None)
    if clinic and clinic.lat is not None and clinic.lng is not None:
        profile.base_lat = clinic.lat
        profile.base_lng = clinic.lng
        profile.save(update_fields=['base_lat', 'base_lng', 'updated_at'])


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def me_toggle_availability(request):
    prof = request.user.professional
    profile, _ = AssociateProfile.objects.get_or_create(professional=prof)
    new = request.data.get('is_available_for_hire')
    if new is None:
        new = not profile.is_available_for_hire
    new = bool(new)
    if new and not (profile.rate_per_slot or profile.rate_per_day):
        return Response(
            {'detail': 'Set at least one of rate_per_slot or rate_per_day before going live.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    profile.is_available_for_hire = new
    profile.save(update_fields=['is_available_for_hire', 'updated_at'])
    if new:
        _fallback_base_location_from_clinic(profile, prof)
    return Response(AssociateProfileSerializer(profile).data)


# ── /search/ — find available associates ─────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def search(request):
    """Find available associates. Returns up to 30 within the associate's travel radius.

    Query params:
      lat, lng       (required) — searcher's reference point
      slot_kind      (optional) 'per_slot' | 'per_day' — filter
      max_rate       (optional) decimal — filter at-or-below this rate
      sort           (optional) 'distance' (default) | 'rate' | 'rating'
    """
    try:
        lat = float(request.query_params['lat'])
        lng = float(request.query_params['lng'])
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'lat and lng required.'},
                        status=status.HTTP_400_BAD_REQUEST)

    slot_kind = request.query_params.get('slot_kind')
    max_rate = request.query_params.get('max_rate')
    sort = request.query_params.get('sort', 'distance')

    qs = (
        AssociateProfile.objects
        .filter(
            is_available_for_hire=True,
            base_lat__isnull=False, base_lng__isnull=False,
            professional__is_admin_verified=True,
            professional__is_active_listing=True,
        )
        .select_related('professional', 'professional__user')
        .exclude(professional__user_id=request.user.id)
    )

    if slot_kind == 'per_slot':
        qs = qs.filter(rate_per_slot__isnull=False)
    elif slot_kind == 'per_day':
        qs = qs.filter(rate_per_day__isnull=False)

    if max_rate:
        try:
            mr = Decimal(str(max_rate))
        except Exception:
            return Response({'detail': 'Invalid max_rate.'},
                            status=status.HTTP_400_BAD_REQUEST)
        if slot_kind == 'per_day':
            qs = qs.filter(rate_per_day__lte=mr)
        elif slot_kind == 'per_slot':
            qs = qs.filter(rate_per_slot__lte=mr)
        else:
            qs = qs.filter(Q(rate_per_slot__lte=mr) | Q(rate_per_day__lte=mr))

    items = []
    for p in qs:
        d = _haversine_km(lat, lng, p.base_lat, p.base_lng)
        if d > p.travel_radius_km:
            continue
        rating = _aggregate_rating(p.professional_id, context='associate')
        items.append({
            'professional_id': p.professional_id,
            'full_name': p.professional.full_name,
            'specialization_display': p.professional.get_specialization_display(),
            'bio': p.bio,
            'slot_hours': p.slot_hours,
            'rate_per_slot': p.rate_per_slot,
            'rate_per_day': p.rate_per_day,
            'base_city': p.base_city,
            'base_state': p.base_state,
            'distance_km': round(d, 2),
            'travel_radius_km': p.travel_radius_km,
            'avg_rating': rating['avg_rating'],
            'review_count': rating['review_count'],
            'profile_photo': (
                p.professional.profile_photo.url if p.professional.profile_photo else None
            ),
        })

    if sort == 'rate':
        items.sort(
            key=lambda i: float(i['rate_per_day'] or i['rate_per_slot'] or 999999)
        )
    elif sort == 'rating':
        items.sort(key=lambda i: -(i['avg_rating'] or 0))
    else:
        items.sort(key=lambda i: i['distance_km'])

    return Response({'associates': items[:30]})


# ── /associates/<prof_id>/ — public profile ──────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def public_profile(request, prof_id):
    try:
        prof = MedicalProfessional.objects.select_related('user', 'clinic').get(pk=prof_id)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Doctor not found.'}, status=status.HTTP_404_NOT_FOUND)

    associate = getattr(prof, 'associate_profile', None)
    associate_data = AssociateProfileSerializer(associate).data if associate else None
    if associate_data:
        # Phone is gated by accepted booking, never by profile view.
        associate_data.pop('phone', None)

    clinic = getattr(prof, 'clinic', None)
    clinic_data = None
    if clinic:
        clinic_data = {
            'name': clinic.name,
            'address': clinic.address,
            'city': clinic.city,
            'state': clinic.state,
        }

    rating_associate = _aggregate_rating(prof.id, context='associate')
    rating_clinic = _aggregate_rating(prof.id, context='clinic')
    rating_general = _aggregate_rating(prof.id, context=None)

    roles_eff = list(prof.roles or [])
    if not roles_eff and prof.role:
        roles_eff = [prof.role]

    return Response({
        'id': prof.id,
        'full_name': prof.full_name,
        'specialization_display': prof.get_specialization_display(),
        'roles': roles_eff,
        'qualification': prof.qualification,
        'years_experience': prof.years_experience,
        'about': prof.about,
        'profile_photo': prof.profile_photo.url if prof.profile_photo else None,
        'clinic': clinic_data,
        'associate_profile': associate_data,
        'rating_associate': rating_associate,
        'rating_clinic': rating_clinic,
        'rating_overall': rating_general,
    })


# ── /bookings/ ───────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def bookings_collection(request):
    me = request.user.professional

    if request.method == 'GET':
        as_role = request.query_params.get('as', 'clinic')
        if as_role == 'associate':
            qs = AssociateBooking.objects.filter(associate=me)
        else:
            qs = AssociateBooking.objects.filter(hiring_clinic=me)
        qs = qs.select_related('associate', 'hiring_clinic', 'hiring_clinic__clinic')
        return Response({'bookings': AssociateBookingSerializer(qs, many=True).data})

    associate_id = request.data.get('associate')
    if not associate_id:
        return Response({'detail': 'associate (id) required.'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        associate = MedicalProfessional.objects.get(pk=associate_id)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Associate not found.'},
                        status=status.HTTP_404_NOT_FOUND)

    if associate.id == me.id:
        return Response({'detail': 'Cannot book yourself.'},
                        status=status.HTTP_400_BAD_REQUEST)

    associate_profile = getattr(associate, 'associate_profile', None)
    if not associate_profile or not associate_profile.is_available_for_hire:
        return Response({'detail': 'This doctor is not currently available for hire.'},
                        status=status.HTTP_400_BAD_REQUEST)

    serializer = AssociateBookingSerializer(
        data={**request.data, 'associate': associate.id}
    )
    serializer.is_valid(raise_exception=True)

    slot_kind = serializer.validated_data['slot_kind']
    rate_quoted = (
        associate_profile.rate_per_slot if slot_kind == 'per_slot'
        else associate_profile.rate_per_day
    )
    if rate_quoted is None:
        return Response(
            {'detail': f'This doctor does not offer {slot_kind} bookings.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    booking = serializer.save(
        hiring_clinic=me,
        associate=associate,
        rate_quoted=rate_quoted,
    )

    _push_to_user(
        associate.user,
        title=f'New booking request — {me.full_name}',
        body=f'{slot_kind.replace("_", " ")} booking. Tap to review.',
        data={
            'type': 'associate_booking',
            'booking_id': str(booking.id),
            'deep_link': f'/associates/bookings/{booking.id}',
        },
    )

    return Response(AssociateBookingSerializer(booking).data,
                    status=status.HTTP_201_CREATED)


@api_view(['GET', 'PATCH'])
@permission_classes([IsAdminVerified])
def booking_detail(request, pk):
    me = request.user.professional
    try:
        booking = AssociateBooking.objects.select_related(
            'associate', 'hiring_clinic', 'hiring_clinic__clinic',
        ).get(pk=pk)
    except AssociateBooking.DoesNotExist:
        return Response({'detail': 'Booking not found.'}, status=status.HTTP_404_NOT_FOUND)

    if me.id not in (booking.associate_id, booking.hiring_clinic_id):
        return Response({'detail': 'Forbidden.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        return Response(AssociateBookingSerializer(booking).data)

    new_status = request.data.get('status')
    if new_status not in {'connected', 'declined', 'cancelled'}:
        return Response(
            {'detail': 'status must be connected | declined | cancelled.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    is_associate = me.id == booking.associate_id
    is_clinic = me.id == booking.hiring_clinic_id

    if new_status in ('connected', 'declined') and not is_associate:
        return Response(
            {'detail': 'Only the associate can accept or decline.'},
            status=status.HTTP_403_FORBIDDEN,
        )

    if new_status == 'cancelled':
        booking.cancelled_by = 'associate' if is_associate else 'clinic'
        booking.cancel_reason = (request.data.get('cancel_reason') or '')[:1000]
    booking.mark_response(new_status)

    other_user = booking.hiring_clinic.user if is_associate else booking.associate.user
    label = {
        'connected': 'accepted your booking',
        'declined': 'declined your booking',
        'cancelled': 'cancelled the booking',
    }[new_status]
    _push_to_user(
        other_user,
        title='Booking update',
        body=f'{me.full_name} {label}.',
        data={
            'type': 'associate_booking',
            'booking_id': str(booking.id),
            'deep_link': f'/associates/bookings/{booking.id}',
        },
    )
    return Response(AssociateBookingSerializer(booking).data)


# ── /reviews/ — global, anyone-to-anyone ─────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAdminVerified])
def submit_review(request):
    me = request.user.professional
    reviewee_id = request.data.get('reviewee')
    rating = request.data.get('rating')
    comment = (request.data.get('comment') or '').strip()
    context = request.data.get('context') or 'general'

    if not reviewee_id:
        return Response({'detail': 'reviewee required.'},
                        status=status.HTTP_400_BAD_REQUEST)
    if reviewee_id == me.id:
        return Response({'detail': 'Cannot review yourself.'},
                        status=status.HTTP_400_BAD_REQUEST)
    try:
        rating = int(rating)
    except (TypeError, ValueError):
        return Response({'detail': 'rating must be an integer 1-5.'},
                        status=status.HTTP_400_BAD_REQUEST)
    if not 1 <= rating <= 5:
        return Response({'detail': 'rating must be between 1 and 5.'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        reviewee = MedicalProfessional.objects.get(pk=reviewee_id)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Reviewee not found.'},
                        status=status.HTTP_404_NOT_FOUND)

    obj, created = ProfessionalReview.objects.update_or_create(
        reviewer=me,
        reviewee=reviewee,
        context=context,
        defaults={'rating': rating, 'comment': comment[:2000]},
    )
    return Response(
        ProfessionalReviewSerializer(obj).data,
        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def reviews_for(request, prof_id):
    try:
        MedicalProfessional.objects.get(pk=prof_id)
    except MedicalProfessional.DoesNotExist:
        return Response({'detail': 'Doctor not found.'},
                        status=status.HTTP_404_NOT_FOUND)
    context = request.query_params.get('context')
    qs = ProfessionalReview.objects.filter(reviewee_id=prof_id)
    if context:
        qs = qs.filter(context=context)
    qs = qs.order_by('-updated_at')[:100]
    rating = _aggregate_rating(prof_id, context=context)
    return Response({
        **rating,
        'reviews': ProfessionalReviewSerializer(qs, many=True).data,
    })


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def delete_review(request, pk):
    me = request.user.professional
    try:
        review = ProfessionalReview.objects.get(pk=pk)
    except ProfessionalReview.DoesNotExist:
        return Response({'detail': 'Review not found.'},
                        status=status.HTTP_404_NOT_FOUND)
    if review.reviewer_id != me.id:
        return Response({'detail': 'Only the reviewer can delete this review.'},
                        status=status.HTTP_403_FORBIDDEN)
    review.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def my_review_for(request, prof_id):
    """The current user's existing review for a given doctor (per context)."""
    me = request.user.professional
    context = request.query_params.get('context', 'general')
    try:
        review = ProfessionalReview.objects.get(
            reviewer=me, reviewee_id=prof_id, context=context,
        )
    except ProfessionalReview.DoesNotExist:
        return Response({'review': None})
    return Response({'review': ProfessionalReviewSerializer(review).data})
