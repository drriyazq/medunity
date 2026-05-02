from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.utils import timezone

from accounts.models import MedicalProfessional

BOOKING_STATUS = [
    ('pending', 'Pending'),
    ('accepted', 'Accepted'),
    ('declined', 'Declined'),
    ('completed', 'Completed'),
    ('cancelled', 'Cancelled'),
]

MOBILITY_MODES = [
    ('mobile', 'Mobile (move during the day)'),
    ('stationary', 'Stationary (work from one place)'),
]

VISIBILITY_MODES = [
    ('open', 'Open — visible to all matching doctors'),
    ('allowlist', 'Allowlist — only my approved doctors can find me'),
]


class ConsultantAvailability(models.Model):
    """One row per consultant — upserted on toggle."""
    consultant = models.OneToOneField(
        MedicalProfessional, on_delete=models.CASCADE, related_name='availability'
    )
    is_available = models.BooleanField(default=False)
    available_since = models.DateTimeField(null=True, blank=True)
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    last_ping_at = models.DateTimeField(null=True, blank=True)
    mobility_mode = models.CharField(
        max_length=12, choices=MOBILITY_MODES, default='mobile'
    )
    travel_radius_km = models.PositiveSmallIntegerField(default=5)
    # Weekly schedule — list of {day: 'mon'..'sun', start: 'HH:MM', end: 'HH:MM'}
    working_schedule = models.JSONField(default=list, blank=True)
    visibility_mode = models.CharField(
        max_length=10, choices=VISIBILITY_MODES, default='open'
    )
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        status = 'Available' if self.is_available else 'Unavailable'
        return f"{self.consultant} — {status}"

    def set_available(self, lat=None, lng=None):
        self.is_available = True
        self.available_since = timezone.now()
        if lat is not None:
            self.lat = lat
        if lng is not None:
            self.lng = lng
        self.last_ping_at = timezone.now()
        self.save()

    def set_unavailable(self):
        self.is_available = False
        self.available_since = None
        self.save()


class ConsultantBlocklist(models.Model):
    """Doctors a consultant has refused — they will not see this consultant in search.
    Populated via decline+block on incoming booking requests in Open mode."""
    consultant = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='consultant_blocklist'
    )
    doctor = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='blocked_by_consultants'
    )
    blocked_at = models.DateTimeField(auto_now_add=True)
    reason = models.CharField(max_length=200, blank=True)

    class Meta:
        unique_together = ('consultant', 'doctor')

    def __str__(self):
        return f"{self.consultant} blocks {self.doctor}"


class ConsultantAllowlist(models.Model):
    """Doctors a consultant has approved — only relevant when visibility_mode='allowlist'.
    In allowlist mode, only doctors in this table see the consultant in search."""
    consultant = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='consultant_allowlist'
    )
    doctor = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='allowed_by_consultants'
    )
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('consultant', 'doctor')

    def __str__(self):
        return f"{self.consultant} allows {self.doctor}"


class ConsultantBooking(models.Model):
    requester = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='bookings_made'
    )
    consultant = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='bookings_received'
    )
    procedure = models.CharField(max_length=300)
    notes = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=BOOKING_STATUS, default='pending')
    requested_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-requested_at']

    def __str__(self):
        return f"Booking #{self.pk}: {self.requester} → {self.consultant} ({self.status})"


class ConsultantReview(models.Model):
    """Two-way review: requester reviews consultant, consultant reviews requester."""
    booking = models.ForeignKey(
        ConsultantBooking, on_delete=models.CASCADE, related_name='reviews'
    )
    reviewer = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='reviews_given'
    )
    reviewee = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='reviews_received'
    )
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    comment = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('booking', 'reviewer')
        ordering = ['-created_at']

    def __str__(self):
        return f"Review by {self.reviewer} for {self.reviewee} — {self.rating}★"
