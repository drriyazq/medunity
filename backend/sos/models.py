import math
from datetime import timedelta

from django.db import models
from django.utils import timezone

from accounts.models import MedicalProfessional

SOS_CATEGORIES = [
    ('medical_emergency', 'Medical Emergency'),
    ('legal_issue', 'Legal Issue'),
    ('clinic_threat', 'Clinic Under Threat'),
    ('urgent_clinical', 'Urgent Clinical Assistance'),
]

SOS_STATUS = [
    ('active', 'Active'),
    ('resolved', 'Resolved'),
    ('expired', 'Expired'),
]

RESPONSE_STATUS = [
    ('accepted', 'Accepted / On My Way'),
    ('declined', 'Declined'),
]

SOS_EXPIRY_HOURS = 2


class SosAlert(models.Model):
    sender = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='sos_sent'
    )
    category = models.CharField(max_length=30, choices=SOS_CATEGORIES)
    lat = models.DecimalField(max_digits=9, decimal_places=6)
    lng = models.DecimalField(max_digits=9, decimal_places=6)
    radius_km = models.FloatField()
    recipient_count = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=10, choices=SOS_STATUS, default='active')
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()

    class Meta:
        ordering = ['-created_at']

    def save(self, *args, **kwargs):
        if not self.pk and not self.expires_at:
            self.expires_at = timezone.now() + timedelta(hours=SOS_EXPIRY_HOURS)
        super().save(*args, **kwargs)

    def __str__(self):
        return f"SOS #{self.pk} — {self.get_category_display()} by {self.sender}"

    @property
    def is_active(self):
        return self.status == 'active' and timezone.now() < self.expires_at

    def accepted_responses(self):
        return self.responses.filter(status='accepted')


class SosResponse(models.Model):
    alert = models.ForeignKey(SosAlert, on_delete=models.CASCADE, related_name='responses')
    responder = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='sos_responses'
    )
    status = models.CharField(max_length=10, choices=RESPONSE_STATUS)
    responder_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    responder_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    responded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('alert', 'responder')
        ordering = ['responded_at']

    def __str__(self):
        return f"{self.responder} — {self.status} for SOS #{self.alert_id}"


class SosRecipient(models.Model):
    """Records each professional an SOS alert was fanned out to.

    Without this we can compute `recipient_count` but can't reconstruct
    *which* doctors received an alert — so a recipient has no way to see
    their own incoming SOS history. One row per (alert, professional)
    is created at send time (see sos.views.send_sos).
    """
    alert = models.ForeignKey(SosAlert, on_delete=models.CASCADE, related_name='recipients')
    professional = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='sos_received'
    )
    notified_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('alert', 'professional')
        ordering = ['-notified_at']

    def __str__(self):
        return f"{self.professional} ← SOS #{self.alert_id}"


def haversine_km(lat1, lng1, lat2, lng2) -> float:
    R = 6371
    dlat = math.radians(float(lat2) - float(lat1))
    dlng = math.radians(float(lng2) - float(lng1))
    a = (math.sin(dlat / 2) ** 2
         + math.cos(math.radians(float(lat1)))
         * math.cos(math.radians(float(lat2)))
         * math.sin(dlng / 2) ** 2)
    return R * 2 * math.asin(math.sqrt(a))


def find_nearby_clinics(lat, lng, exclude_prof_id):
    """
    Auto-expand 1 → 2 → 5 km until ≥ 3 recipients found.
    Returns (clinic_list, radius_used_km).
    """
    from accounts.models import Clinic
    all_clinics = list(
        Clinic.objects.filter(lat__isnull=False, lng__isnull=False)
        .exclude(owner_id=exclude_prof_id)
        .select_related('owner__user')
    )
    for radius in [1, 2, 5]:
        within = [c for c in all_clinics if haversine_km(lat, lng, c.lat, c.lng) <= radius]
        if len(within) >= 3:
            return within, radius
    return [c for c in all_clinics if haversine_km(lat, lng, c.lat, c.lng) <= 5], 5
