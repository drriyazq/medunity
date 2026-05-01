from rest_framework import serializers

from .models import Clinic, DeviceToken, MedicalProfessional, ROLE_CHOICES, VALID_ROLE_KEYS


class ClinicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Clinic
        fields = ['id', 'name', 'address', 'city', 'state', 'pincode',
                  'phone', 'landline_phone', 'website', 'lat', 'lng',
                  'location_set_at', 'location_locked']
        read_only_fields = ['id', 'location_set_at', 'location_locked']


class MedicalProfessionalSerializer(serializers.ModelSerializer):
    clinic = ClinicSerializer(read_only=True)
    verification_status = serializers.CharField(read_only=True)
    specialization_display = serializers.CharField(source='get_specialization_display', read_only=True)
    council_display = serializers.CharField(source='get_medical_council_display', read_only=True)
    role_display = serializers.CharField(source='get_role_display', read_only=True)
    roles_display = serializers.SerializerMethodField()

    class Meta:
        model = MedicalProfessional
        fields = [
            'id', 'firebase_uid', 'phone', 'full_name', 'email',
            'role', 'role_display', 'roles', 'roles_display',
            'medical_council', 'council_display',
            'license_number', 'specialization', 'specialization_display',
            'years_experience', 'qualification', 'about', 'profile_photo',
            'is_admin_verified', 'is_active_listing', 'verification_status',
            'verification_submitted_at', 'verified_at', 'rejection_reason',
            'clinic', 'created_at', 'updated_at',
        ]
        read_only_fields = [
            'id', 'firebase_uid', 'phone', 'is_admin_verified', 'is_active_listing',
            'verification_status', 'verification_submitted_at', 'verified_at',
            'rejection_reason', 'created_at', 'updated_at',
        ]

    def get_roles_display(self, obj):
        labels = dict(ROLE_CHOICES)
        return [{'key': r, 'label': labels.get(r, r)} for r in (obj.roles or [])]


class MedicalProfessionalUpdateSerializer(serializers.ModelSerializer):
    """Editable fields only — credentials (license, council) are read-only post-submit."""
    class Meta:
        model = MedicalProfessional
        fields = [
            'about', 'profile_photo', 'years_experience',
            'qualification', 'email', 'roles',
        ]

    def validate_roles(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError('roles must be a list.')
        if not value:
            raise serializers.ValidationError('At least one role is required.')
        bad = [r for r in value if r not in VALID_ROLE_KEYS]
        if bad:
            raise serializers.ValidationError(f'Unknown role keys: {bad}')
        # Dedupe while preserving order
        return list(dict.fromkeys(value))


class DeviceTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceToken
        fields = ['token', 'platform', 'app_version']
