from django.db import models
from django.utils import timezone

from accounts.models import MedicalProfessional

REQUEST_TYPES = [
    ('coverage', 'Patient Coverage'),
    ('space_lending', 'Space / Operatory Lending'),
]

REQUEST_STATUS = [
    ('open', 'Open'),
    ('accepted', 'Accepted'),
    ('closed', 'Closed'),
]

POINT_SOURCES = [
    ('sos_response', 'SOS Response'),
    ('coverage', 'Coverage / Shift Help'),
    ('space_lending', 'Space Lending'),
    ('manual', 'Manual Award'),
]

POINTS_BY_SOURCE = {
    'sos_response': 10,
    'coverage': 15,
    'space_lending': 15,
    'manual': 5,
}


class CoverageRequest(models.Model):
    requester = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='coverage_requests_made'
    )
    accepted_by = models.ForeignKey(
        MedicalProfessional, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='coverage_requests_accepted'
    )
    request_type = models.CharField(max_length=15, choices=REQUEST_TYPES)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    city = models.CharField(max_length=100, blank=True)
    start_dt = models.DateTimeField(null=True, blank=True)
    end_dt = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=10, choices=REQUEST_STATUS, default='open')
    created_at = models.DateTimeField(auto_now_add=True)
    accepted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.get_request_type_display()} — {self.title} ({self.status})"

    def accept(self, acceptor: MedicalProfessional):
        self.accepted_by = acceptor
        self.status = 'accepted'
        self.accepted_at = timezone.now()
        self.save(update_fields=['accepted_by', 'status', 'accepted_at'])
        award_points(acceptor, 'coverage' if self.request_type == 'coverage' else 'space_lending',
                     source_id=self.pk, reason=f'Accepted: {self.title}')


class BrowniePoint(models.Model):
    recipient = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='brownie_points'
    )
    source_type = models.CharField(max_length=15, choices=POINT_SOURCES)
    source_id = models.PositiveIntegerField(null=True, blank=True)
    points = models.PositiveSmallIntegerField()
    reason = models.CharField(max_length=300)
    awarded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-awarded_at']

    def __str__(self):
        return f"{self.recipient} +{self.points} ({self.source_type})"


def award_points(recipient: MedicalProfessional, source_type: str,
                 source_id: int | None = None, reason: str = '') -> BrowniePoint:
    points = POINTS_BY_SOURCE.get(source_type, 5)
    return BrowniePoint.objects.create(
        recipient=recipient,
        source_type=source_type,
        source_id=source_id,
        points=points,
        reason=reason,
    )
