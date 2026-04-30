import logging

from django.db.models import Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.permissions import IsAdminVerified

from .models import BrowniePoint, CoverageRequest, award_points

logger = logging.getLogger(__name__)


# ── helpers ───────────────────────────────────────────────────────────────────

def _request_data(req: CoverageRequest, prof) -> dict:
    return {
        'id': req.pk,
        'request_type': req.request_type,
        'request_type_display': req.get_request_type_display(),
        'title': req.title,
        'description': req.description,
        'city': req.city,
        'start_dt': req.start_dt,
        'end_dt': req.end_dt,
        'status': req.status,
        'requester_name': req.requester.full_name,
        'requester_specialization': req.requester.get_specialization_display(),
        'requester_id': req.requester_id,
        'accepted_by_name': req.accepted_by.full_name if req.accepted_by else None,
        'is_mine': req.requester_id == prof.id,
        'i_accepted': req.accepted_by_id == prof.id if req.accepted_by else False,
        'created_at': req.created_at,
    }


# ── Coverage requests ─────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def requests(request):
    prof = request.user.professional

    if request.method == 'GET':
        req_type = request.query_params.get('type', '').strip()
        include_closed = request.query_params.get('include_closed', '') == '1'
        city = request.query_params.get('city', '').strip()

        qs = CoverageRequest.objects.select_related('requester', 'accepted_by')
        if not include_closed:
            qs = qs.filter(status='open')
        if req_type in ('coverage', 'space_lending'):
            qs = qs.filter(request_type=req_type)
        if city:
            qs = qs.filter(city__icontains=city)

        return Response([_request_data(r, prof) for r in qs[:50]])

    # POST — create
    title = request.data.get('title', '').strip()
    if not title:
        return Response({'detail': 'title is required.'}, status=status.HTTP_400_BAD_REQUEST)

    req_type = request.data.get('request_type', 'coverage')
    if req_type not in ('coverage', 'space_lending'):
        req_type = 'coverage'

    start_dt = end_dt = None
    try:
        if request.data.get('start_dt'):
            from datetime import datetime
            start_dt = datetime.fromisoformat(request.data['start_dt'])
        if request.data.get('end_dt'):
            end_dt = datetime.fromisoformat(request.data['end_dt'])
    except ValueError:
        return Response({'detail': 'Invalid date format.'}, status=status.HTTP_400_BAD_REQUEST)

    clinic = getattr(prof, 'clinic', None)
    req_obj = CoverageRequest.objects.create(
        requester=prof,
        request_type=req_type,
        title=title,
        description=request.data.get('description', '').strip(),
        city=request.data.get('city', clinic.city if clinic else '').strip(),
        start_dt=start_dt,
        end_dt=end_dt,
    )

    # Push to nearby doctors in same circle
    _notify_new_request(req_obj, prof)

    return Response(_request_data(req_obj, prof), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def request_detail(request, pk):
    prof = request.user.professional
    try:
        req = CoverageRequest.objects.select_related('requester', 'accepted_by').get(pk=pk)
    except CoverageRequest.DoesNotExist:
        return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response(_request_data(req, prof))


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def accept_request(request, pk):
    prof = request.user.professional
    try:
        req = CoverageRequest.objects.select_related('requester').get(pk=pk, status='open')
    except CoverageRequest.DoesNotExist:
        return Response({'detail': 'Request not found or already accepted.'}, status=status.HTTP_404_NOT_FOUND)

    if req.requester_id == prof.id:
        return Response({'detail': 'Cannot accept your own request.'}, status=status.HTTP_400_BAD_REQUEST)

    req.accept(prof)

    # Notify requester
    from accounts.models import DeviceToken
    from medunity.fcm import send_push_notification
    tokens = list(DeviceToken.objects.filter(user=req.requester.user).values_list('token', flat=True))
    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title='✅ Coverage Request Accepted',
            body=f'{prof.full_name} will cover for: {req.title}',
            data={
                'type': 'coverage_accepted',
                'request_id': str(req.pk),
                'deep_link': f'/support/requests/{req.pk}',
            },
            channel_id='default',
        )

    return Response(_request_data(req, prof))


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def close_request(request, pk):
    prof = request.user.professional
    try:
        req = CoverageRequest.objects.get(pk=pk, requester=prof)
    except CoverageRequest.DoesNotExist:
        return Response({'detail': 'Not found or not yours.'}, status=status.HTTP_404_NOT_FOUND)

    req.status = 'closed'
    req.save(update_fields=['status'])
    return Response(_request_data(req, prof))


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def my_requests(request):
    prof = request.user.professional
    qs = CoverageRequest.objects.filter(
        requester=prof
    ).select_related('requester', 'accepted_by').order_by('-created_at')
    return Response([_request_data(r, prof) for r in qs])


# ── Leaderboard ───────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def leaderboard(request):
    from accounts.models import MedicalProfessional
    from django.db.models import Sum, Count, OuterRef, Subquery

    rows = (
        BrowniePoint.objects
        .values('recipient')
        .annotate(total=Sum('points'))
        .order_by('-total')[:20]
    )

    result = []
    for rank, row in enumerate(rows, start=1):
        try:
            prof = MedicalProfessional.objects.get(pk=row['recipient'])
            result.append({
                'rank': rank,
                'id': prof.pk,
                'full_name': prof.full_name,
                'specialization': prof.get_specialization_display(),
                'clinic_city': prof.clinic.city if hasattr(prof, 'clinic') else '',
                'total_points': row['total'],
                'profile_photo': prof.profile_photo.url if prof.profile_photo else None,
            })
        except MedicalProfessional.DoesNotExist:
            continue

    return Response(result)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def my_points(request):
    prof = request.user.professional
    total = prof.brownie_points.aggregate(total=Sum('points'))['total'] or 0

    # My rank
    higher_count = (
        BrowniePoint.objects
        .values('recipient')
        .annotate(total=Sum('points'))
        .filter(total__gt=total)
        .count()
    )
    my_rank = higher_count + 1

    history = prof.brownie_points.order_by('-awarded_at')[:20]
    return Response({
        'total_points': total,
        'rank': my_rank,
        'history': [
            {
                'source_type': p.source_type,
                'points': p.points,
                'reason': p.reason,
                'awarded_at': p.awarded_at,
            }
            for p in history
        ],
    })


# ── FCM helper ────────────────────────────────────────────────────────────────

def _notify_new_request(req: CoverageRequest, requester):
    """Push to members of requester's circles."""
    from accounts.models import DeviceToken
    from circles.models import CircleMembership
    from medunity.fcm import send_push_notification

    circle_ids = requester.circle_memberships.filter(
        is_active=True
    ).values_list('circle_id', flat=True)

    member_user_ids = CircleMembership.objects.filter(
        circle_id__in=circle_ids, is_active=True
    ).exclude(member=requester).values_list('member__user_id', flat=True)

    tokens = list(DeviceToken.objects.filter(user_id__in=member_user_ids).values_list('token', flat=True))
    type_label = '🏥' if req.request_type == 'coverage' else '🏢'

    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title=f'{type_label} {req.get_request_type_display()} Request',
            body=f'{requester.full_name}: {req.title}',
            data={
                'type': 'coverage_request',
                'request_id': str(req.pk),
                'deep_link': f'/support/requests/{req.pk}',
            },
            channel_id='default',
        )
