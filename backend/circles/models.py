from django.db import models

from accounts.models import MedicalProfessional
from sos.models import haversine_km

CIRCLE_TYPES = [
    ('auto', 'Auto-created'),
    ('manual', 'Created by member'),
]

MEMBER_ROLES = [
    ('admin', 'Admin'),
    ('member', 'Member'),
]

POST_TYPES = [
    ('discussion', 'Discussion'),
    ('event', 'Event'),
    ('announcement', 'Announcement'),
]


class Circle(models.Model):
    name = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    circle_type = models.CharField(max_length=10, choices=CIRCLE_TYPES, default='manual')
    created_by = models.ForeignKey(
        MedicalProfessional, on_delete=models.SET_NULL,
        null=True, blank=True, related_name='created_circles',
    )
    radius_km = models.FloatField(default=2.0)
    center_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    center_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    member_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.name

    def recalc_member_count(self):
        self.member_count = self.memberships.filter(is_active=True).count()
        self.save(update_fields=['member_count'])

    def is_member(self, prof: MedicalProfessional) -> bool:
        return self.memberships.filter(member=prof, is_active=True).exists()

    def is_admin(self, prof: MedicalProfessional) -> bool:
        return self.memberships.filter(member=prof, role='admin', is_active=True).exists()


class CircleMembership(models.Model):
    circle = models.ForeignKey(Circle, on_delete=models.CASCADE, related_name='memberships')
    member = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='circle_memberships'
    )
    role = models.CharField(max_length=10, choices=MEMBER_ROLES, default='member')
    is_active = models.BooleanField(default=True)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('circle', 'member')
        ordering = ['joined_at']

    def __str__(self):
        return f"{self.member} in {self.circle} ({self.role})"


class CirclePost(models.Model):
    circle = models.ForeignKey(Circle, on_delete=models.CASCADE, related_name='posts')
    author = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='circle_posts'
    )
    post_type = models.CharField(max_length=15, choices=POST_TYPES, default='discussion')
    content = models.TextField()
    comment_count = models.PositiveIntegerField(default=0)
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Post #{self.pk} in {self.circle}"

    def recalc_comment_count(self):
        self.comment_count = self.comments.filter(is_deleted=False).count()
        self.save(update_fields=['comment_count'])


class PostComment(models.Model):
    post = models.ForeignKey(CirclePost, on_delete=models.CASCADE, related_name='comments')
    author = models.ForeignKey(
        MedicalProfessional, on_delete=models.CASCADE, related_name='post_comments'
    )
    content = models.TextField()
    is_deleted = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"Comment #{self.pk} on Post #{self.post_id}"


# ── Auto-circle logic ─────────────────────────────────────────────────────────

def auto_join_or_create_circle(prof: MedicalProfessional):
    """
    Called after a clinic's location is set.
    Finds circles within 2 km of the clinic and auto-joins the nearest one.
    If none found, creates a city-level circle and adds the doctor as admin.
    """
    clinic = getattr(prof, 'clinic', None)
    if not clinic or clinic.lat is None:
        return

    lat, lng = float(clinic.lat), float(clinic.lng)

    # Already in a circle? Don't add again
    if prof.circle_memberships.filter(is_active=True).exists():
        return

    active_circles = list(Circle.objects.filter(is_active=True))
    nearby = [
        c for c in active_circles
        if c.center_lat is not None
        and haversine_km(lat, lng, c.center_lat, c.center_lng) <= 2.0
    ]

    if nearby:
        nearest = min(nearby, key=lambda c: haversine_km(lat, lng, c.center_lat, c.center_lng))
        membership, created = CircleMembership.objects.get_or_create(
            circle=nearest, member=prof, defaults={'role': 'member', 'is_active': True}
        )
        if not membership.is_active:
            membership.is_active = True
            membership.save(update_fields=['is_active'])
        nearest.recalc_member_count()
    else:
        city = clinic.city or 'Local'
        circle = Circle.objects.create(
            name=f"{city} Doctors Circle",
            description=f"Auto-created circle for doctors in {city}.",
            circle_type='auto',
            created_by=prof,
            radius_km=2.0,
            center_lat=clinic.lat,
            center_lng=clinic.lng,
            member_count=1,
        )
        CircleMembership.objects.create(circle=circle, member=prof, role='admin')
