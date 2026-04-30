import logging
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response

from accounts.permissions import IsAdminVerified

from .models import (
    EquipmentPool, ListingInquiry, MarketplaceListing,
    PoolMembership, PoolUsageSlot,
)

logger = logging.getLogger(__name__)

PAGE_SIZE = 20


# ── helpers ───────────────────────────────────────────────────────────────────

def _pool_data(pool: EquipmentPool, prof) -> dict:
    membership = pool.memberships.filter(member=prof, is_active=True).first()
    return {
        'id': pool.pk,
        'name': pool.name,
        'description': pool.description,
        'category': pool.category,
        'category_display': pool.get_category_display(),
        'target_amount': str(pool.target_amount),
        'committed_amount': str(pool.committed_amount),
        'funding_pct': round(pool.funding_pct, 1),
        'status': pool.status,
        'status_display': pool.get_status_display(),
        'member_count': pool.member_count,
        'max_members': pool.max_members,
        'is_full': pool.is_full,
        'is_member': membership is not None,
        'my_contribution': str(membership.contribution_amount) if membership else None,
        'created_by_id': pool.created_by_id,
        'is_mine': pool.created_by_id == prof.id,
        'created_at': pool.created_at,
    }


def _slot_data(slot: PoolUsageSlot, prof) -> dict:
    return {
        'id': slot.pk,
        'member_name': slot.member.full_name,
        'member_id': slot.member_id,
        'is_mine': slot.member_id == prof.id,
        'start_dt': slot.start_dt,
        'end_dt': slot.end_dt,
        'notes': slot.notes,
        'status': slot.status,
    }


def _listing_data(listing: MarketplaceListing, prof) -> dict:
    return {
        'id': listing.pk,
        'title': listing.title,
        'description': listing.description,
        'category': listing.category,
        'category_display': listing.get_category_display(),
        'price': str(listing.price),
        'condition': listing.condition,
        'condition_display': listing.get_condition_display(),
        'image': listing.image.url if listing.image else None,
        'status': listing.status,
        'inquiry_count': listing.inquiry_count,
        'seller_name': listing.seller.full_name,
        'seller_specialization': listing.seller.get_specialization_display(),
        'is_mine': listing.seller_id == prof.id,
        'created_at': listing.created_at,
    }


# ── Pools ─────────────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def pools(request):
    prof = request.user.professional

    if request.method == 'GET':
        category = request.query_params.get('category', '').strip()
        qs = EquipmentPool.objects.filter(status__in=['open', 'funded', 'active'])
        if category:
            qs = qs.filter(category=category)
        return Response([_pool_data(p, prof) for p in qs[:50]])

    # POST — create
    name = request.data.get('name', '').strip()
    if not name:
        return Response({'detail': 'name is required.'}, status=status.HTTP_400_BAD_REQUEST)

    category = request.data.get('category', '').strip()
    valid_categories = [c[0] for c in [
        ('dental_chairs', ''), ('imaging', ''), ('surgical_instruments', ''),
        ('diagnostic', ''), ('sterilization', ''), ('lab_equipment', ''),
        ('consumables', ''), ('other', ''),
    ]]
    if category not in valid_categories:
        return Response({'detail': 'Invalid category.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        target_amount = Decimal(str(request.data['target_amount']))
        contribution = Decimal(str(request.data['my_contribution']))
        if target_amount <= 0 or contribution <= 0:
            raise ValueError
    except (KeyError, InvalidOperation, ValueError):
        return Response(
            {'detail': 'target_amount and my_contribution must be positive numbers.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    try:
        max_members = max(2, min(int(request.data.get('max_members', 10)), 50))
    except (TypeError, ValueError):
        max_members = 10

    with transaction.atomic():
        pool = EquipmentPool.objects.create(
            name=name,
            description=request.data.get('description', '').strip(),
            category=category,
            target_amount=target_amount,
            created_by=prof,
            max_members=max_members,
            member_count=1,
            committed_amount=contribution,
        )
        PoolMembership.objects.create(pool=pool, member=prof, contribution_amount=contribution)

    logger.info(f'[equipment] Pool #{pool.pk} "{pool.name}" created by {prof}')
    return Response(_pool_data(pool, prof), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def pool_detail(request, pk):
    prof = request.user.professional
    try:
        pool = EquipmentPool.objects.prefetch_related('memberships__member').get(pk=pk)
    except EquipmentPool.DoesNotExist:
        return Response({'detail': 'Pool not found.'}, status=status.HTTP_404_NOT_FOUND)

    data = _pool_data(pool, prof)
    data['members'] = [
        {
            'id': m.member_id,
            'name': m.member.full_name,
            'specialization': m.member.get_specialization_display(),
            'contribution': str(m.contribution_amount),
            'joined_at': m.joined_at,
        }
        for m in pool.memberships.filter(is_active=True)
    ]
    return Response(data)


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def join_pool(request, pk):
    prof = request.user.professional
    try:
        pool = EquipmentPool.objects.get(pk=pk)
    except EquipmentPool.DoesNotExist:
        return Response({'detail': 'Pool not found.'}, status=status.HTTP_404_NOT_FOUND)

    if pool.status != 'open':
        return Response({'detail': 'This pool is no longer accepting members.'}, status=status.HTTP_409_CONFLICT)
    if pool.is_full:
        return Response({'detail': 'Pool is full.'}, status=status.HTTP_409_CONFLICT)

    try:
        contribution = Decimal(str(request.data['contribution_amount']))
        if contribution <= 0:
            raise ValueError
    except (KeyError, InvalidOperation, ValueError):
        return Response({'detail': 'contribution_amount must be a positive number.'}, status=status.HTTP_400_BAD_REQUEST)

    membership, created = PoolMembership.objects.get_or_create(
        pool=pool, member=prof,
        defaults={'contribution_amount': contribution, 'is_active': True},
    )
    if not created:
        if membership.is_active:
            return Response({'detail': 'Already a member.'}, status=status.HTTP_409_CONFLICT)
        membership.is_active = True
        membership.contribution_amount = contribution
        membership.save(update_fields=['is_active', 'contribution_amount'])

    pool.recalc()
    return Response(_pool_data(pool, prof))


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def leave_pool(request, pk):
    prof = request.user.professional
    try:
        membership = PoolMembership.objects.get(pool_id=pk, member=prof, is_active=True)
    except PoolMembership.DoesNotExist:
        return Response({'detail': 'Not a member.'}, status=status.HTTP_404_NOT_FOUND)

    if membership.pool.created_by_id == prof.id:
        return Response({'detail': 'Creator cannot leave. Close the pool instead.'}, status=status.HTTP_400_BAD_REQUEST)

    membership.is_active = False
    membership.save(update_fields=['is_active'])
    membership.pool.recalc()
    return Response({'detail': 'Left pool.'})


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def update_pool_status(request, pk):
    """Creator marks pool funded/active/closed."""
    prof = request.user.professional
    try:
        pool = EquipmentPool.objects.get(pk=pk, created_by=prof)
    except EquipmentPool.DoesNotExist:
        return Response({'detail': 'Pool not found or not yours.'}, status=status.HTTP_404_NOT_FOUND)

    new_status = request.data.get('status', '').strip()
    valid = {'funded', 'active', 'closed'}
    if new_status not in valid:
        return Response({'detail': f'status must be one of: {", ".join(valid)}'}, status=status.HTTP_400_BAD_REQUEST)

    pool.status = new_status
    pool.save(update_fields=['status'])
    return Response(_pool_data(pool, prof))


# ── Usage slots ───────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def pool_slots(request, pk):
    prof = request.user.professional
    try:
        pool = EquipmentPool.objects.get(pk=pk)
    except EquipmentPool.DoesNotExist:
        return Response({'detail': 'Pool not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not pool.memberships.filter(member=prof, is_active=True).exists():
        return Response({'detail': 'Members only.'}, status=status.HTTP_403_FORBIDDEN)

    if pool.status not in ('active',):
        return Response({'detail': 'Usage scheduling is only available for active pools.'}, status=status.HTTP_409_CONFLICT)

    if request.method == 'GET':
        upcoming = pool.slots.filter(
            status='booked', start_dt__gte=timezone.now()
        ).select_related('member')
        return Response([_slot_data(s, prof) for s in upcoming])

    # POST — book a slot
    try:
        from datetime import datetime
        start_dt = datetime.fromisoformat(request.data['start_dt'])
        end_dt = datetime.fromisoformat(request.data['end_dt'])
    except (KeyError, ValueError):
        return Response({'detail': 'start_dt and end_dt required as ISO datetime strings.'}, status=status.HTTP_400_BAD_REQUEST)

    if end_dt <= start_dt:
        return Response({'detail': 'end_dt must be after start_dt.'}, status=status.HTTP_400_BAD_REQUEST)

    # Clash check
    clash = pool.slots.filter(
        status='booked',
        start_dt__lt=end_dt,
        end_dt__gt=start_dt,
    ).exists()
    if clash:
        return Response({'detail': 'Time slot conflicts with an existing booking.'}, status=status.HTTP_409_CONFLICT)

    slot = PoolUsageSlot.objects.create(
        pool=pool,
        member=prof,
        start_dt=start_dt,
        end_dt=end_dt,
        notes=request.data.get('notes', '').strip(),
    )
    return Response(_slot_data(slot, prof), status=status.HTTP_201_CREATED)


@api_view(['DELETE'])
@permission_classes([IsAdminVerified])
def cancel_slot(request, pk, slot_id):
    prof = request.user.professional
    try:
        slot = PoolUsageSlot.objects.get(pk=slot_id, pool_id=pk, member=prof, status='booked')
    except PoolUsageSlot.DoesNotExist:
        return Response({'detail': 'Slot not found.'}, status=status.HTTP_404_NOT_FOUND)

    slot.status = 'cancelled'
    slot.save(update_fields=['status'])
    return Response({'detail': 'Slot cancelled.'})


# ── Marketplace listings ──────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
@parser_classes([MultiPartParser, FormParser])
def listings(request):
    prof = request.user.professional

    if request.method == 'GET':
        category = request.query_params.get('category', '').strip()
        page = max(1, int(request.query_params.get('page', 1)))
        offset = (page - 1) * PAGE_SIZE
        qs = MarketplaceListing.objects.filter(status='active').select_related('seller')
        if category:
            qs = qs.filter(category=category)
        total = qs.count()
        return Response({
            'results': [_listing_data(l, prof) for l in qs[offset: offset + PAGE_SIZE]],
            'page': page,
            'has_more': total > offset + PAGE_SIZE,
        })

    # POST — create listing
    title = request.data.get('title', '').strip()
    if not title:
        return Response({'detail': 'title is required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
        price = Decimal(str(request.data['price']))
        if price < 0:
            raise ValueError
    except (KeyError, InvalidOperation, ValueError):
        return Response({'detail': 'price must be a non-negative number.'}, status=status.HTTP_400_BAD_REQUEST)

    condition = request.data.get('condition', 'good')
    if condition not in ('new', 'like_new', 'good', 'fair'):
        condition = 'good'

    category = request.data.get('category', 'other')

    listing = MarketplaceListing.objects.create(
        seller=prof,
        title=title,
        description=request.data.get('description', '').strip(),
        category=category,
        price=price,
        condition=condition,
        image=request.FILES.get('image'),
    )
    return Response(_listing_data(listing, prof), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminVerified])
def my_listings(request):
    prof = request.user.professional
    qs = MarketplaceListing.objects.filter(seller=prof).exclude(status='removed')
    return Response([_listing_data(l, prof) for l in qs])


@api_view(['GET', 'PATCH', 'DELETE'])
@permission_classes([IsAdminVerified])
def listing_detail(request, pk):
    prof = request.user.professional
    try:
        listing = MarketplaceListing.objects.select_related('seller').get(pk=pk)
    except MarketplaceListing.DoesNotExist:
        return Response({'detail': 'Listing not found.'}, status=status.HTTP_404_NOT_FOUND)

    if request.method == 'GET':
        data = _listing_data(listing, prof)
        if listing.seller_id == prof.id:
            data['inquiries'] = [
                {
                    'id': i.pk,
                    'inquirer_name': i.inquirer.full_name,
                    'inquirer_specialization': i.inquirer.get_specialization_display(),
                    'message': i.message,
                    'created_at': i.created_at,
                }
                for i in listing.inquiries.select_related('inquirer').order_by('-created_at')[:20]
            ]
        return Response(data)

    if listing.seller_id != prof.id:
        return Response({'detail': 'Not yours.'}, status=status.HTTP_403_FORBIDDEN)

    if request.method == 'PATCH':
        if 'status' in request.data:
            new_status = request.data['status']
            if new_status in ('sold', 'active'):
                listing.status = new_status
        if 'price' in request.data:
            try:
                listing.price = Decimal(str(request.data['price']))
            except InvalidOperation:
                pass
        if 'description' in request.data:
            listing.description = request.data['description']
        listing.save()
        return Response(_listing_data(listing, prof))

    # DELETE
    listing.status = 'removed'
    listing.save(update_fields=['status'])
    return Response({'detail': 'Listing removed.'})


@api_view(['POST'])
@permission_classes([IsAdminVerified])
def inquire(request, pk):
    prof = request.user.professional
    try:
        listing = MarketplaceListing.objects.get(pk=pk, status='active')
    except MarketplaceListing.DoesNotExist:
        return Response({'detail': 'Listing not found or no longer active.'}, status=status.HTTP_404_NOT_FOUND)

    if listing.seller_id == prof.id:
        return Response({'detail': 'Cannot inquire on your own listing.'}, status=status.HTTP_400_BAD_REQUEST)

    message = request.data.get('message', '').strip()
    if not message:
        return Response({'detail': 'message is required.'}, status=status.HTTP_400_BAD_REQUEST)

    inq = ListingInquiry.objects.create(listing=listing, inquirer=prof, message=message)
    listing.inquiry_count = listing.inquiries.count()
    listing.save(update_fields=['inquiry_count'])

    # Notify seller
    from accounts.models import DeviceToken
    from medunity.fcm import send_push_notification
    tokens = list(DeviceToken.objects.filter(user=listing.seller.user).values_list('token', flat=True))
    for token in tokens:
        send_push_notification(
            fcm_token=token,
            title='💬 New Inquiry on Your Listing',
            body=f'{prof.full_name}: {message[:80]}',
            data={
                'type': 'listing_inquiry',
                'listing_id': str(listing.pk),
                'deep_link': f'/equipment/listings/{listing.pk}',
            },
            channel_id='default',
        )

    return Response({'detail': 'Inquiry sent.', 'id': inq.pk}, status=status.HTTP_201_CREATED)
