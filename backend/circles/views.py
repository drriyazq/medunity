import logging

from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.permissions import IsAdminVerified
from sos.models import haversine_km

from .models import Circle, CircleMembership, CirclePost, PostComment

logger = logging.getLogger(__name__)

PAGE_SIZE = 20


# ── helpers ───────────────────────────────────────────────────────────────────

def _circle_data(circle: Circle, prof) -> dict:
    membership = circle.memberships.filter(member=prof, is_active=True).first()
    return {
        'id': circle.pk,
        'name': circle.name,
        'description': circle.description,
        'circle_type': circle.circle_type,
        'radius_km': circle.radius_km,
        'member_count': circle.member_count,
        'is_member': membership is not None,
        'my_role': membership.role if membership else None,
        'created_at': circle.created_at,
    }


def _member_data(membership: CircleMembership) -> dict:
    p = membership.member
    return {
        'id': p.pk,
        'full_name': p.full_name,
        'specialization': p.get_specialization_display(),
        'role': membership.role,
        'joined_at': membership.joined_at,
    }


def _post_data(post: CirclePost, prof) -> dict:
    return {
        'id': post.pk,
        'post_type': post.post_type,
        'content': post.content,
        'comment_count': post.comment_count,
        'author_name': post.author.full_name,
        'author_id': post.author_id,
        'is_mine': post.author_id == prof.id,
        'created_at': post.created_at,
    }


def _comment_data(comment: PostComment, prof) -> dict:
    return {
        'id': comment.pk,
        'content': comment.content,
        'author_name': comment.author.full_name,
        'author_id': comment.author_id,
        'is_mine': comment.author_id == prof.id,
        'created_at': comment.created_at,
    }


# ── Circle list / create ──────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def circles(request):
    prof = request.user.professional

    if request.method == 'GET':
        my_circle_ids = prof.circle_memberships.filter(
            is_active=True
        ).values_list('circle_id', flat=True)
        qs = Circle.objects.filter(pk__in=my_circle_ids, is_active=True)
        return Response([_circle_data(c, prof) for c in qs])

    # POST — create a new manual circle
    name = request.data.get('name', '').strip()
    if not name:
        return Response({'detail': 'name is required.'}, status=status.HTTP_400_BAD_REQUEST)

    description = request.data.get('description', '').strip()
    try:
        radius_km = float(request.data.get('radius_km', 2.0))
        radius_km = max(0.5, min(radius_km, 10.0))
    except (TypeError, ValueError):
        radius_km = 2.0

    clinic = getattr(prof, 'clinic', None)
    with transaction.atomic():
        circle = Circle.objects.create(
            name=name,
            description=description,
            circle_type='manual',
            created_by=prof,
            radius_km=radius_km,
            center_lat=clinic.lat if clinic else None,
            center_lng=clinic.lng if clinic else None,
            member_count=1,
        )
        CircleMembership.objects.create(circle=circle, member=prof, role='admin')

    logger.info(f'[circles] {prof} created circle #{circle.pk} "{circle.name}"')
    return Response(_circle_data(circle, prof), status=status.HTTP_201_CREATED)


# ── Nearby circles ────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def nearby_circles(request):
    prof = request.user.professional
    clinic = getattr(prof, 'clinic', None)

    if not clinic or clinic.lat is None:
        return Response({'detail': 'Set your clinic location first.'}, status=status.HTTP_400_BAD_REQUEST)

    lat, lng = float(clinic.lat), float(clinic.lng)
    joined_ids = set(prof.circle_memberships.filter(is_active=True).values_list('circle_id', flat=True))

    all_circles = Circle.objects.filter(is_active=True).exclude(pk__in=joined_ids)
    nearby = []
    for c in all_circles:
        if c.center_lat is None:
            continue
        dist = haversine_km(lat, lng, c.center_lat, c.center_lng)
        if dist <= 10.0:
            data = _circle_data(c, prof)
            data['distance_km'] = round(dist, 2)
            nearby.append(data)

    nearby.sort(key=lambda x: x['distance_km'])
    return Response(nearby[:20])


# ── Circle detail / join / leave ──────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def circle_detail(request, pk):
    prof = request.user.professional
    try:
        circle = Circle.objects.get(pk=pk, is_active=True)
    except Circle.DoesNotExist:
        return Response({'detail': 'Circle not found.'}, status=status.HTTP_404_NOT_FOUND)

    members = circle.memberships.filter(is_active=True).select_related('member')
    data = _circle_data(circle, prof)
    data['members'] = [_member_data(m) for m in members]
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def join_circle(request, pk):
    prof = request.user.professional
    try:
        circle = Circle.objects.get(pk=pk, is_active=True)
    except Circle.DoesNotExist:
        return Response({'detail': 'Circle not found.'}, status=status.HTTP_404_NOT_FOUND)

    membership, created = CircleMembership.objects.get_or_create(
        circle=circle, member=prof, defaults={'role': 'member', 'is_active': True}
    )
    if not created and not membership.is_active:
        membership.is_active = True
        membership.save(update_fields=['is_active'])
    elif not created and membership.is_active:
        return Response({'detail': 'Already a member.'}, status=status.HTTP_409_CONFLICT)

    circle.recalc_member_count()
    return Response({'detail': 'Joined.', 'circle': _circle_data(circle, prof)})


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def leave_circle(request, pk):
    prof = request.user.professional
    try:
        membership = CircleMembership.objects.get(circle_id=pk, member=prof, is_active=True)
    except CircleMembership.DoesNotExist:
        return Response({'detail': 'Not a member.'}, status=status.HTTP_404_NOT_FOUND)

    if membership.role == 'admin':
        # Promote next member to admin before leaving, or deactivate circle if sole member
        other = CircleMembership.objects.filter(
            circle_id=pk, is_active=True
        ).exclude(member=prof).order_by('joined_at').first()
        if other:
            other.role = 'admin'
            other.save(update_fields=['role'])
        else:
            Circle.objects.filter(pk=pk).update(is_active=False)

    membership.is_active = False
    membership.save(update_fields=['is_active'])
    Circle.objects.get(pk=pk).recalc_member_count()
    return Response({'detail': 'Left circle.'})


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def kick_member(request, pk, member_id):
    prof = request.user.professional
    if not Circle.objects.filter(pk=pk, is_active=True).exists():
        return Response({'detail': 'Circle not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not CircleMembership.objects.filter(circle_id=pk, member=prof, role='admin', is_active=True).exists():
        return Response({'detail': 'Admin only.'}, status=status.HTTP_403_FORBIDDEN)

    updated = CircleMembership.objects.filter(
        circle_id=pk, member_id=member_id, is_active=True
    ).update(is_active=False)
    if not updated:
        return Response({'detail': 'Member not found.'}, status=status.HTTP_404_NOT_FOUND)

    Circle.objects.get(pk=pk).recalc_member_count()
    return Response({'detail': 'Member removed.'})


# ── Posts ─────────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def posts(request, pk):
    prof = request.user.professional
    try:
        circle = Circle.objects.get(pk=pk, is_active=True)
    except Circle.DoesNotExist:
        return Response({'detail': 'Circle not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not circle.is_member(prof):
        return Response({'detail': 'Members only.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        page = int(request.query_params.get('page', 1))
        offset = (page - 1) * PAGE_SIZE
        qs = circle.posts.filter(is_deleted=False).select_related('author')[offset: offset + PAGE_SIZE]
        return Response({
            'results': [_post_data(p, prof) for p in qs],
            'page': page,
            'has_more': circle.posts.filter(is_deleted=False).count() > offset + PAGE_SIZE,
        })

    # POST — create
    content = request.data.get('content', '').strip()
    if not content:
        return Response({'detail': 'content is required.'}, status=status.HTTP_400_BAD_REQUEST)

    post_type = request.data.get('post_type', 'discussion')
    if post_type not in ('discussion', 'event', 'announcement'):
        post_type = 'discussion'

    post = CirclePost.objects.create(
        circle=circle,
        author=prof,
        post_type=post_type,
        content=content,
    )

    # Push notify circle members (async-free: small fan-out acceptable)
    _notify_new_post(circle, post, prof)

    return Response(_post_data(post, prof), status=status.HTTP_201_CREATED)


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def delete_post(request, pk, post_id):
    prof = request.user.professional
    try:
        post = CirclePost.objects.select_related('circle').get(pk=post_id, circle_id=pk)
    except CirclePost.DoesNotExist:
        return Response({'detail': 'Post not found.'}, status=status.HTTP_404_NOT_FOUND)

    if post.author_id != prof.id and not post.circle.is_admin(prof):
        return Response({'detail': 'Not allowed.'}, status=status.HTTP_403_FORBIDDEN)

    post.is_deleted = True
    post.save(update_fields=['is_deleted'])
    return Response({'detail': 'Post deleted.'})


# ── Comments ──────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def comments(request, pk, post_id):
    prof = request.user.professional
    try:
        circle = Circle.objects.get(pk=pk, is_active=True)
        post = CirclePost.objects.get(pk=post_id, circle=circle, is_deleted=False)
    except (Circle.DoesNotExist, CirclePost.DoesNotExist):
        return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not circle.is_member(prof):
        return Response({'detail': 'Members only.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'GET':
        qs = post.comments.filter(is_deleted=False).select_related('author')
        return Response([_comment_data(c, prof) for c in qs])

    # POST
    content = request.data.get('content', '').strip()
    if not content:
        return Response({'detail': 'content is required.'}, status=status.HTTP_400_BAD_REQUEST)

    comment = PostComment.objects.create(post=post, author=prof, content=content)
    post.recalc_comment_count()

    return Response(_comment_data(comment, prof), status=status.HTTP_201_CREATED)


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def delete_comment(request, pk, post_id, comment_id):
    prof = request.user.professional
    try:
        circle = Circle.objects.get(pk=pk, is_active=True)
        post = CirclePost.objects.get(pk=post_id, circle=circle)
        comment = PostComment.objects.get(pk=comment_id, post=post)
    except (Circle.DoesNotExist, CirclePost.DoesNotExist, PostComment.DoesNotExist):
        return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)

    if comment.author_id != prof.id and not circle.is_admin(prof):
        return Response({'detail': 'Not allowed.'}, status=status.HTTP_403_FORBIDDEN)

    comment.is_deleted = True
    comment.save(update_fields=['is_deleted'])
    post.recalc_comment_count()
    return Response({'detail': 'Comment deleted.'})


# ── FCM helper ────────────────────────────────────────────────────────────────

def _notify_new_post(circle: Circle, post: CirclePost, author):
    from accounts.models import DeviceToken
    from medunity.fcm import send_push_notification

    member_ids = circle.memberships.filter(
        is_active=True
    ).exclude(member=author).values_list('member__user_id', flat=True)

    tokens = list(DeviceToken.objects.filter(user_id__in=member_ids).values_list('token', flat=True))
    type_label = {'discussion': '💬', 'event': '📅', 'announcement': '📢'}.get(post.post_type, '💬')

    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title=f'{type_label} {circle.name}',
            body=f'{author.full_name}: {post.content[:80]}',
            data={
                'type': 'circle_post',
                'circle_id': str(circle.pk),
                'post_id': str(post.pk),
                'deep_link': f'/circles/{circle.pk}/posts/{post.pk}',
            },
            channel_id='default',
        )
