"""Associate doctor marketplace + global doctor-to-doctor reviews.

No money flow: rates are displayed text. Bookings are connection signals
(pending → connected | declined | cancelled). Once connected, the two
sides see each other's phone and arrange details directly.

Reviews are public-anonymous: reviewer is stored on the row (so admins
can audit abuse) but never appears in any API response.
"""
from decimal import Decimal

from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from accounts.models import INDIAN_STATES, MedicalProfessional


SLOT_KIND_CHOICES = [
    ('per_slot', 'Per Slot'),
    ('per_day', 'Per Day'),
]

BOOKING_STATUS = [
    ('pending', 'Pending'),
    ('connected', 'Connected'),
    ('declined', 'Declined'),
    ('cancelled', 'Cancelled'),
]

REVIEW_CONTEXTS = [
    ('associate', 'As Associate Doctor'),
    ('clinic', 'As Clinic Owner'),
    ('consultant', 'As Visiting Consultant'),
    ('hospital', 'As Hospital Owner'),
    ('general', 'General'),
]


class AssociateProfile(models.Model):
    professional = models.OneToOneField(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='associate_profile',
    )

    is_available_for_hire = models.BooleanField(default=False)
    bio = models.TextField(blank=True)

    # Rates — at least one must be set when is_available_for_hire=True.
    slot_hours = models.PositiveSmallIntegerField(null=True, blank=True)
    rate_per_slot = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )
    rate_per_day = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )

    # Where the associate is based + how far they'll travel.
    base_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    base_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    base_city = models.CharField(max_length=100, blank=True)
    base_state = models.CharField(max_length=100, choices=INDIAN_STATES, blank=True)
    travel_radius_km = models.PositiveSmallIntegerField(default=10)

    notes = models.TextField(blank=True, help_text='Free-form notes shown to clinics.')

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        flag = 'available' if self.is_available_for_hire else 'unavailable'
        return f'{self.professional.full_name} — associate ({flag})'


class AssociateBooking(models.Model):
    """Connection request from a hiring clinic to an associate doctor.

    No money flow — the rate is a snapshot for record. Both sides settle
    payment privately after they exchange phone numbers via the
    `connected` state.
    """
    associate = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='associate_bookings_received',
    )
    hiring_clinic = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='associate_bookings_made',
    )

    proposed_start = models.DateTimeField()
    proposed_end = models.DateTimeField()
    slot_kind = models.CharField(max_length=10, choices=SLOT_KIND_CHOICES)
    rate_quoted = models.DecimalField(max_digits=10, decimal_places=2, default=Decimal('0'))

    notes = models.TextField(blank=True)

    status = models.CharField(max_length=10, choices=BOOKING_STATUS, default='pending')
    cancelled_by = models.CharField(max_length=10, blank=True)  # 'clinic'|'associate'|''
    cancel_reason = models.TextField(blank=True)

    requested_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-requested_at']

    def __str__(self):
        return f'Booking #{self.pk}: {self.hiring_clinic} → {self.associate} ({self.status})'

    def mark_response(self, new_status: str):
        self.status = new_status
        self.responded_at = timezone.now()
        self.save(update_fields=['status', 'responded_at'])


class ProfessionalReview(models.Model):
    """Anyone-to-anyone review between two MedicalProfessionals.

    The reviewer FK is stored for audit but never serialized in API
    responses — that's the "public-anonymous, admin-knows" model.

    A reviewer can leave one review per (reviewee, context) pair; submitting
    again replaces the existing row.
    """
    reviewer = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='reviews_authored',
    )
    reviewee = models.ForeignKey(
        MedicalProfessional,
        on_delete=models.CASCADE,
        related_name='reviews_about_me',
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True)
    context = models.CharField(max_length=15, choices=REVIEW_CONTEXTS, default='general')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('reviewer', 'reviewee', 'context')
        ordering = ['-updated_at']

    def __str__(self):
        return f'Review {self.rating}★ for prof#{self.reviewee_id} ({self.context})'
