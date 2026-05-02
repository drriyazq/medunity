from decimal import Decimal

from django.db import models

from accounts.models import MedicalProfessional

EQUIPMENT_CATEGORIES = [
    ('dental_chairs', 'Dental Chairs & Units'),
    ('imaging', 'Imaging & Radiology'),
    ('surgical_instruments', 'Surgical Instruments'),
    ('diagnostic', 'Diagnostic Equipment'),
    ('sterilization', 'Sterilization & Hygiene'),
    ('lab_equipment', 'Lab Equipment'),
    ('consumables', 'Consumables & Supplies'),
    ('other', 'Other'),
]

POOL_STATUS = [
    ('open', 'Open — Accepting Members'),
    ('funded', 'Funded — Procurement Underway'),
    ('active', 'Active — In Use'),
    ('closed', 'Closed'),
]

POOL_PURPOSES = [
    ('bulk_buy', 'Bulk Discount Buy'),
    ('shared_use', 'Shared Use'),
]

LISTING_CONDITIONS = [
    ('new', 'Brand New'),
    ('like_new', 'Like New'),
    ('good', 'Good'),
    ('fair', 'Fair'),
]

LISTING_STATUS = [
    ('active', 'Active'),
    ('sold', 'Sold'),
    ('removed', 'Removed'),
]


# ── Co-purchase Pool ──────────────────────────────────────────────────────────

class EquipmentPool(models.Model):
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=30, choices=EQUIPMENT_CATEGORIES)
    purpose = models.CharField(max_length=12, choices=POOL_PURPOSES, default='bulk_buy')
    target_amount = models.DecimalField(max_digits=12, decimal_places=2)
    created_by = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='pools_created'
    )
    status = models.CharField(max_length=10, choices=POOL_STATUS, default='open')
    max_members = models.PositiveIntegerField(default=10)
    member_count = models.PositiveIntegerField(default=0)
    committed_amount = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0'))
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.name} ({self.get_status_display()})"

    def recalc(self):
        active = self.memberships.filter(is_active=True)
        self.member_count = active.count()
        self.committed_amount = active.aggregate(
            total=models.Sum('contribution_amount')
        )['total'] or Decimal('0')
        self.save(update_fields=['member_count', 'committed_amount'])

    @property
    def funding_pct(self) -> float:
        if self.target_amount == 0:
            return 0.0
        return min(100.0, float(self.committed_amount / self.target_amount * 100))

    @property
    def is_full(self) -> bool:
        return self.member_count >= self.max_members


class PoolMembership(models.Model):
    pool = models.ForeignKey(EquipmentPool, on_delete=models.CASCADE, related_name='memberships')
    member = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='pool_memberships'
    )
    contribution_amount = models.DecimalField(max_digits=12, decimal_places=2)
    is_active = models.BooleanField(default=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('pool', 'member')
        ordering = ['joined_at']

    def __str__(self):
        return f"{self.member} in {self.pool} — ₹{self.contribution_amount}"


class PoolUsageSlot(models.Model):
    pool = models.ForeignKey(EquipmentPool, on_delete=models.CASCADE, related_name='slots')
    member = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='pool_slots'
    )
    start_dt = models.DateTimeField()
    end_dt = models.DateTimeField()
    notes = models.CharField(max_length=300, blank=True)
    status = models.CharField(
        max_length=10,
        choices=[('booked', 'Booked'), ('completed', 'Completed'), ('cancelled', 'Cancelled')],
        default='booked',
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['start_dt']

    def __str__(self):
        return f"{self.member} — {self.pool} @ {self.start_dt:%Y-%m-%d %H:%M}"


# ── Marketplace ───────────────────────────────────────────────────────────────

class MarketplaceListing(models.Model):
    seller = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='listings'
    )
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=30, choices=EQUIPMENT_CATEGORIES)
    price = models.DecimalField(max_digits=12, decimal_places=2)
    condition = models.CharField(max_length=10, choices=LISTING_CONDITIONS)
    image = models.ImageField(upload_to='equipment/', blank=True, null=True)
    status = models.CharField(max_length=10, choices=LISTING_STATUS, default='active')
    inquiry_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.title} — ₹{self.price} ({self.get_condition_display()})"


class ListingInquiry(models.Model):
    listing = models.ForeignKey(
        MarketplaceListing, on_delete=models.CASCADE, related_name='inquiries'
    )
    inquirer = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='inquiries_sent'
    )
    message = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Inquiry by {self.inquirer} on {self.listing}"
