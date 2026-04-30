import logging

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from accounts.permissions import IsAdminVerified

from .models import FLAG_REASONS, Vendor, VendorFlag, VendorReview, find_duplicate

logger = logging.getLogger(__name__)

PAGE_SIZE = 20


# ── helpers ───────────────────────────────────────────────────────────────────

def _vendor_data(v: Vendor, prof, include_reviews: bool = False) -> dict:
    my_review = v.reviews.filter(reviewer=prof).first() if prof else None
    d = {
        'id': v.pk,
        'name': v.name,
        'category': v.category,
        'category_display': v.get_category_display(),
        'description': v.description,
        'address': v.address,
        'city': v.city,
        'state': v.state,
        'pincode': v.pincode,
        'phone': v.phone,
        'website': v.website,
        'is_verified': v.is_verified,
        'flag_count': v.flag_count,
        'avg_rating': float(v.avg_rating) if v.avg_rating else None,
        'avg_quality': float(v.avg_quality) if v.avg_quality else None,
        'avg_delivery': float(v.avg_delivery) if v.avg_delivery else None,
        'review_count': v.review_count,
        'my_review': {
            'rating': my_review.rating,
            'quality_rating': my_review.quality_rating,
            'delivery_rating': my_review.delivery_rating,
            'comment': my_review.comment,
        } if my_review else None,
        'i_flagged': v.flags.filter(reporter=prof).exists() if prof else False,
        'created_at': v.created_at,
    }
    if include_reviews:
        d['reviews'] = [
            {
                'id': r.pk,
                'reviewer_name': r.reviewer.full_name,
                'rating': r.rating,
                'quality_rating': r.quality_rating,
                'delivery_rating': r.delivery_rating,
                'comment': r.comment,
                'created_at': r.created_at,
            }
            for r in v.reviews.select_related('reviewer').order_by('-created_at')[:20]
        ]
    return d


# ── List / create ─────────────────────────────────────────────────────────────

@api_view(['GET', 'POST'])
@permission_classes([IsAdminVerified])
def vendors(request):
    prof = request.user.professional

    if request.method == 'GET':
        category = request.query_params.get('category', '').strip()
        city = request.query_params.get('city', '').strip()
        sort = request.query_params.get('sort', 'rating')  # rating | delivery | quality | newest
        page = max(1, int(request.query_params.get('page', 1)))
        offset = (page - 1) * PAGE_SIZE

        qs = Vendor.objects.filter(flag_count__lt=5)
        if category:
            qs = qs.filter(category=category)
        if city:
            qs = qs.filter(city__icontains=city)

        if sort == 'delivery':
            qs = qs.order_by('-avg_delivery', '-review_count')
        elif sort == 'quality':
            qs = qs.order_by('-avg_quality', '-review_count')
        elif sort == 'newest':
            qs = qs.order_by('-created_at')
        else:
            qs = qs.order_by('-avg_rating', '-review_count')

        total = qs.count()
        return Response({
            'results': [_vendor_data(v, prof) for v in qs[offset: offset + PAGE_SIZE]],
            'page': page,
            'has_more': total > offset + PAGE_SIZE,
        })

    # POST — submit a new vendor
    name = request.data.get('name', '').strip()
    city = request.data.get('city', '').strip()
    if not name or not city:
        return Response({'detail': 'name and city are required.'}, status=status.HTTP_400_BAD_REQUEST)

    category = request.data.get('category', 'other')
    address = request.data.get('address', '').strip()

    # Anti-duplication check
    duplicate = find_duplicate(name, city, address)
    if duplicate:
        return Response({
            'detail': 'A similar vendor already exists.',
            'existing': _vendor_data(duplicate, prof),
        }, status=status.HTTP_409_CONFLICT)

    vendor = Vendor.objects.create(
        name=name,
        category=category,
        description=request.data.get('description', '').strip(),
        address=address,
        city=city,
        state=request.data.get('state', '').strip(),
        pincode=request.data.get('pincode', '').strip(),
        phone=request.data.get('phone', '').strip(),
        website=request.data.get('website', '').strip(),
        added_by=prof,
    )
    logger.info(f'[vendors] New vendor #{vendor.pk} "{vendor.name}" added by {prof}')
    return Response(_vendor_data(vendor, prof), status=status.HTTP_201_CREATED)


# ── Search ────────────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def search_vendors(request):
    prof = request.user.professional
    q = request.query_params.get('q', '').strip()
    city = request.query_params.get('city', '').strip()

    if not q:
        return Response({'results': []})

    qs = Vendor.objects.filter(
        name__icontains=q, flag_count__lt=5
    ).order_by('-avg_rating', '-review_count')
    if city:
        qs = qs.filter(city__icontains=city)

    return Response({'results': [_vendor_data(v, prof) for v in qs[:20]]})


# ── Detail ────────────────────────────────────────────────────────────────────

@api_view(['GET'])
@permission_classes([IsAdminVerified])
def vendor_detail(request, pk):
    prof = request.user.professional
    try:
        vendor = Vendor.objects.prefetch_related('reviews__reviewer', 'flags').get(pk=pk)
    except Vendor.DoesNotExist:
        return Response({'detail': 'Vendor not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response(_vendor_data(vendor, prof, include_reviews=True))


# ── Review ────────────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAdminVerified])
def review_vendor(request, pk):
    prof = request.user.professional
    try:
        vendor = Vendor.objects.get(pk=pk)
    except Vendor.DoesNotExist:
        return Response({'detail': 'Vendor not found.'}, status=status.HTTP_404_NOT_FOUND)

    if vendor.reviews.filter(reviewer=prof).exists():
        return Response({'detail': 'Already reviewed this vendor.'}, status=status.HTTP_409_CONFLICT)

    try:
        rating = int(request.data['rating'])
        if not (1 <= rating <= 5):
            raise ValueError
    except (KeyError, TypeError, ValueError):
        return Response({'detail': 'rating must be 1–5.'}, status=status.HTTP_400_BAD_REQUEST)

    quality = request.data.get('quality_rating')
    delivery = request.data.get('delivery_rating')

    VendorReview.objects.create(
        vendor=vendor,
        reviewer=prof,
        rating=rating,
        quality_rating=int(quality) if quality else None,
        delivery_rating=int(delivery) if delivery else None,
        comment=request.data.get('comment', '').strip(),
    )
    vendor.recalc_ratings()
    return Response({'detail': 'Review submitted.'})


# ── Flag ──────────────────────────────────────────────────────────────────────

@api_view(['POST'])
@permission_classes([IsAdminVerified])
def flag_vendor(request, pk):
    prof = request.user.professional
    try:
        vendor = Vendor.objects.get(pk=pk)
    except Vendor.DoesNotExist:
        return Response({'detail': 'Vendor not found.'}, status=status.HTTP_404_NOT_FOUND)

    if vendor.flags.filter(reporter=prof).exists():
        return Response({'detail': 'Already flagged this vendor.'}, status=status.HTTP_409_CONFLICT)

    reason = request.data.get('reason', 'other')
    if reason not in dict(FLAG_REASONS):
        reason = 'other'

    VendorFlag.objects.create(
        vendor=vendor,
        reporter=prof,
        reason=reason,
        details=request.data.get('details', '').strip(),
    )
    vendor.flag_count = vendor.flags.count()
    vendor.save(update_fields=['flag_count'])

    logger.warning(f'[vendors] Vendor #{pk} "{vendor.name}" flagged ({vendor.flag_count} flags)')
    return Response({'detail': 'Report submitted. Thank you.'})
