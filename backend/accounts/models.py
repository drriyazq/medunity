import uuid
from decimal import Decimal

from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone

# ── Choice constants ──────────────────────────────────────────────────────────

DOCTOR_SPECIALIZATIONS = [
    ('general_physician', 'General Physician'),
    ('dentist', 'Dentist'),
    ('oral_surgeon', 'Oral Surgeon'),
    ('endodontist', 'Endodontist (Root Canal Specialist)'),
    ('orthodontist', 'Orthodontist'),
    ('periodontist', 'Periodontist'),
    ('prosthodontist', 'Prosthodontist'),
    ('pedodontist', 'Pedodontist (Child Dental)'),
    ('cardiologist', 'Cardiologist'),
    ('dermatologist', 'Dermatologist'),
    ('gynaecologist', 'Gynaecologist / Obstetrician'),
    ('orthopaedic', 'Orthopaedic Surgeon'),
    ('paediatrician', 'Paediatrician'),
    ('ent_specialist', 'ENT Specialist'),
    ('physiotherapist', 'Physiotherapist'),
    ('neurologist', 'Neurologist'),
    ('psychiatrist', 'Psychiatrist'),
    ('ophthalmologist', 'Ophthalmologist'),
    ('urologist', 'Urologist'),
    ('gastroenterologist', 'Gastroenterologist'),
    ('pulmonologist', 'Pulmonologist'),
    ('endocrinologist', 'Endocrinologist'),
    ('oncologist', 'Oncologist'),
    ('nephrologist', 'Nephrologist'),
    ('rheumatologist', 'Rheumatologist'),
    ('radiologist', 'Radiologist'),
    ('pathologist', 'Pathologist'),
    ('anaesthesiologist', 'Anaesthesiologist'),
    ('general_surgeon', 'General Surgeon'),
    ('plastic_surgeon', 'Plastic Surgeon'),
    ('neurosurgeon', 'Neurosurgeon'),
    ('hematologist', 'Hematologist'),
    ('infectious_disease', 'Infectious Disease'),
    ('geriatric', 'Geriatric Medicine'),
    ('emergency_medicine', 'Emergency Medicine'),
    ('other', 'Other'),
]

MEDICAL_COUNCILS = [
    ('nmc', 'National Medical Commission (NMC)'),
    ('dci', 'Dental Council of India (DCI)'),
    ('inc', 'Indian Nursing Council (INC)'),
    ('mci_legacy', 'MCI (legacy registration)'),
    ('ap_mc', 'Andhra Pradesh Medical Council'),
    ('assam_mc', 'Assam Medical Council'),
    ('bihar_mc', 'Bihar Medical Council'),
    ('cg_mc', 'Chhattisgarh Medical Council'),
    ('delhi_mc', 'Delhi Medical Council'),
    ('goa_mc', 'Goa Medical Council'),
    ('gujarat_mc', 'Gujarat Medical Council'),
    ('hp_mc', 'Himachal Pradesh Medical Council'),
    ('jharkhand_mc', 'Jharkhand Medical Council'),
    ('karnataka_mc', 'Karnataka Medical Council'),
    ('kerala_mc', 'Kerala Medical Council'),
    ('mp_mc', 'Madhya Pradesh Medical Council'),
    ('maharashtra_mc', 'Maharashtra Medical Council'),
    ('manipur_mc', 'Manipur Medical Council'),
    ('odisha_mc', 'Odisha Medical Council'),
    ('punjab_mc', 'Punjab Medical Council'),
    ('rajasthan_mc', 'Rajasthan Medical Council'),
    ('tn_mc', 'Tamil Nadu Medical Council'),
    ('telangana_mc', 'Telangana Medical Council'),
    ('up_mc', 'Uttar Pradesh Medical Council'),
    ('uttarakhand_mc', 'Uttarakhand Medical Council'),
    ('wb_mc', 'West Bengal Medical Council'),
    ('other_council', 'Other / State Council'),
]

ROLE_CHOICES = [
    ('clinic_owner', 'Clinic Owner / Primary Physician'),
    ('hospital_owner', 'Hospital Owner / Director'),
    ('visiting_consultant', 'Visiting Consultant / Specialist'),
    ('associate_doctor', 'Associate Doctor (Short-term Coverage)'),
    ('academic_teaching', 'Academic / Teaching (Dental College Faculty)'),
]
VALID_ROLE_KEYS = {key for key, _ in ROLE_CHOICES}

INDIAN_STATES = [
    ('Andhra Pradesh', 'Andhra Pradesh'), ('Arunachal Pradesh', 'Arunachal Pradesh'),
    ('Assam', 'Assam'), ('Bihar', 'Bihar'), ('Chhattisgarh', 'Chhattisgarh'),
    ('Goa', 'Goa'), ('Gujarat', 'Gujarat'), ('Haryana', 'Haryana'),
    ('Himachal Pradesh', 'Himachal Pradesh'), ('Jharkhand', 'Jharkhand'),
    ('Karnataka', 'Karnataka'), ('Kerala', 'Kerala'), ('Madhya Pradesh', 'Madhya Pradesh'),
    ('Maharashtra', 'Maharashtra'), ('Manipur', 'Manipur'), ('Meghalaya', 'Meghalaya'),
    ('Mizoram', 'Mizoram'), ('Nagaland', 'Nagaland'), ('Odisha', 'Odisha'),
    ('Punjab', 'Punjab'), ('Rajasthan', 'Rajasthan'), ('Sikkim', 'Sikkim'),
    ('Tamil Nadu', 'Tamil Nadu'), ('Telangana', 'Telangana'), ('Tripura', 'Tripura'),
    ('Uttar Pradesh', 'Uttar Pradesh'), ('Uttarakhand', 'Uttarakhand'),
    ('West Bengal', 'West Bengal'),
    ('Delhi', 'Delhi'), ('Jammu and Kashmir', 'Jammu and Kashmir'),
    ('Ladakh', 'Ladakh'), ('Chandigarh', 'Chandigarh'),
]

VERIFICATION_STATUS = [
    ('pending', 'Pending Review'),
    ('verified', 'Verified'),
    ('rejected', 'Rejected'),
]


# ── Models ────────────────────────────────────────────────────────────────────

class MedicalProfessional(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='professional')

    firebase_uid = models.CharField(max_length=128, unique=True, null=True, blank=True)
    phone = models.CharField(max_length=20)  # E.164 normalised
    phone_verified_at = models.DateTimeField(null=True, blank=True)
    full_name = models.CharField(max_length=200)
    email = models.EmailField(blank=True)

    role = models.CharField(max_length=30, choices=ROLE_CHOICES)
    # Multi-select roles. `role` (single) is retained for back-compat with
    # existing onboarding; `roles` is the canonical list and is what the app
    # reads/writes from now on. Backfilled from `role` on first migration.
    roles = models.JSONField(default=list, blank=True)
    # The single role the user is acting in primarily today. Drives
    # role-aware UI on the Home screen and the "Primary Role" pill on cards.
    # Must be one of the entries in `roles` (validated in the view layer).
    primary_role = models.CharField(
        max_length=30, choices=ROLE_CHOICES, blank=True, default=''
    )
    medical_council = models.CharField(max_length=30, choices=MEDICAL_COUNCILS)
    license_number = models.CharField(max_length=100)
    specialization = models.CharField(max_length=50, choices=DOCTOR_SPECIALIZATIONS)
    years_experience = models.PositiveIntegerField(null=True, blank=True)
    qualification = models.CharField(max_length=300, blank=True)
    about = models.TextField(blank=True)
    profile_photo = models.ImageField(upload_to='profiles/', blank=True, null=True)

    # License documents — stored in restricted /media/licenses/ path
    license_doc = models.FileField(upload_to='licenses/', blank=True, null=True)
    degree_doc = models.FileField(upload_to='degrees/', blank=True, null=True)
    clinic_proof_doc = models.FileField(upload_to='clinic_proofs/', blank=True, null=True)

    # Verification gate (mirror salahdeskai pattern)
    is_admin_verified = models.BooleanField(default=False)
    is_active_listing = models.BooleanField(default=True)
    verification_submitted_at = models.DateTimeField(null=True, blank=True)
    verified_at = models.DateTimeField(null=True, blank=True)
    verified_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.SET_NULL,
        related_name='verified_professionals',
    )
    rejection_reason = models.TextField(blank=True)
    admin_notes = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.full_name} ({self.get_specialization_display()})"

    @property
    def verification_status(self):
        if self.is_admin_verified:
            return 'verified'
        if self.rejection_reason:
            return 'rejected'
        return 'pending'

    @property
    def is_active(self):
        return self.is_admin_verified and self.is_active_listing


class Clinic(models.Model):
    owner = models.OneToOneField(MedicalProfessional, on_delete=models.CASCADE, related_name='clinic')
    name = models.CharField(max_length=200)
    address = models.TextField()
    city = models.CharField(max_length=100)
    state = models.CharField(max_length=100, choices=INDIAN_STATES)
    pincode = models.CharField(max_length=10)
    phone = models.CharField(max_length=20)
    landline_phone = models.CharField(max_length=20, blank=True)
    website = models.URLField(blank=True)

    # GPS — baked in from Phase 1 to avoid retrofit in Phase 2 (SOS)
    lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_set_at = models.DateTimeField(null=True, blank=True)
    # When True, the GPS-update endpoint refuses overwrites. Used for fixed
    # test/dummy accounts and any clinic where the operator wants the location
    # pinned regardless of where the doctor's phone is currently sitting.
    location_locked = models.BooleanField(default=False)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.name} ({self.city})"

    def set_location(self, lat: Decimal, lng: Decimal):
        self.lat = lat
        self.lng = lng
        self.location_set_at = timezone.now()
        self.save(update_fields=['lat', 'lng', 'location_set_at'])


class DeviceToken(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='device_tokens')
    token = models.TextField(unique=True)
    platform = models.CharField(max_length=10, default='android')
    app_version = models.CharField(max_length=20, blank=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-last_seen_at']

    def __str__(self):
        return f"{self.user.username} — {self.platform} [{self.token[:20]}...]"


class OtpDeliveryLog(models.Model):
    """Audit row for every WhatsApp OTP send attempt. Use to debug deliverability
    issues (template rejected, token expired, phone-id wrong) — Meta's error
    payload lands in `response_json`.
    """
    phone = models.CharField(max_length=20, db_index=True)
    template_name = models.CharField(max_length=100)
    result_ok = models.BooleanField(default=False)
    message_id = models.CharField(max_length=200, blank=True)
    error_message = models.TextField(blank=True)
    response_json = models.JSONField(default=dict, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        flag = "✓" if self.result_ok else "✗"
        return f"{flag} {self.phone} {self.template_name} @ {self.created_at:%Y-%m-%d %H:%M}"
