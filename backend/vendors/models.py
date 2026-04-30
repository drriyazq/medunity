from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from accounts.models import MedicalProfessional

VENDOR_CATEGORIES = [
    ('dental_lab', 'Dental Lab'),
    ('material_dealer', 'Dental Material Dealer'),
    ('equipment_technician', 'Equipment Technician / Service'),
    ('pharmacy', 'Pharmacy / Compounding'),
    ('imaging_centre', 'Imaging Centre / Radiology'),
    ('other', 'Other'),
]

FLAG_REASONS = [
    ('fraud', 'Fraudulent or scam'),
    ('closed', 'Business no longer exists'),
    ('wrong_info', 'Incorrect information'),
    ('duplicate', 'Duplicate listing'),
    ('other', 'Other'),
]


class Vendor(models.Model):
    name = models.CharField(max_length=200)
    category = models.CharField(max_length=25, choices=VENDOR_CATEGORIES)
    description = models.TextField(blank=True)
    address = models.TextField(blank=True)
    city = models.CharField(max_length=100)
    state = models.CharField(max_length=100, blank=True)
    pincode = models.CharField(max_length=10, blank=True)
    phone = models.CharField(max_length=20, blank=True)
    website = models.URLField(blank=True)

    added_by = models.ForeignKey(
        MedicalProfessional, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='vendors_added',
    )
    is_verified = models.BooleanField(default=False)
    flag_count = models.PositiveIntegerField(default=0)

    # Cached aggregates — recalculated on each review/flag
    avg_rating = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True)
    avg_quality = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True)
    avg_delivery = models.DecimalField(max_digits=3, decimal_places=1, null=True, blank=True)
    review_count = models.PositiveIntegerField(default=0)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-avg_rating', '-review_count', 'name']

    def __str__(self):
        return f"{self.name} ({self.city})"

    def recalc_ratings(self):
        from django.db.models import Avg, Count
        agg = self.reviews.aggregate(
            avg=Avg('rating'),
            avg_q=Avg('quality_rating'),
            avg_d=Avg('delivery_rating'),
            cnt=Count('id'),
        )
        self.avg_rating = agg['avg']
        self.avg_quality = agg['avg_q']
        self.avg_delivery = agg['avg_d']
        self.review_count = agg['cnt'] or 0
        self.save(update_fields=['avg_rating', 'avg_quality', 'avg_delivery', 'review_count'])


class VendorReview(models.Model):
    vendor = models.ForeignKey(Vendor, on_delete=models.CASCADE, related_name='reviews')
    reviewer = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='vendor_reviews'
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    quality_rating = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    delivery_rating = models.PositiveSmallIntegerField(
        null=True, blank=True, validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('vendor', 'reviewer')
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.reviewer} → {self.vendor} ({self.rating}★)"


class VendorFlag(models.Model):
    vendor = models.ForeignKey(Vendor, on_delete=models.CASCADE, related_name='flags')
    reporter = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='vendor_flags'
    )
    reason = models.CharField(max_length=20, choices=FLAG_REASONS)
    details = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('vendor', 'reporter')
        ordering = ['-created_at']

    def __str__(self):
        return f"Flag on {self.vendor} by {self.reporter}"


# ── Anti-duplication ──────────────────────────────────────────────────────────

def find_duplicate(name: str, city: str, address: str = '') -> 'Vendor | None':
    """
    Return existing vendor if name+city is suspiciously similar to a submitted one.
    Uses rapidfuzz token_set_ratio: >= 85 on name AND same city (case-insensitive).
    """
    from rapidfuzz import fuzz

    candidates = Vendor.objects.filter(city__iexact=city)
    name_lower = name.lower().strip()

    for v in candidates:
        name_score = fuzz.token_set_ratio(name_lower, v.name.lower())
        if name_score >= 85:
            # Optional: also check address similarity if both provided
            if address and v.address:
                addr_score = fuzz.token_set_ratio(address.lower(), v.address.lower())
                if addr_score >= 70:
                    return v
            else:
                return v
    return None
