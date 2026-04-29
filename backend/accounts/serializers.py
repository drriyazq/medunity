from rest_framework import serializers

from .models import Clinic, DeviceToken, MedicalProfessional


class ClinicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Clinic
        fields = ['id', 'name', 'address', 'city', 'state', 'pincode',
                  'phone', 'landline_phone', 'website', 'lat', 'lng', 'location_set_at']
        read_only_fields = ['id', 'location_set_at']


class MedicalProfessionalSerializer(serializers.ModelSerializer):
    clinic = ClinicSerializer(read_only=True)
    verification_status = serializers.CharField(read_only=True)
    specialization_display = serializers.CharField(source='get_specialization_display', read_only=True)
    council_display = serializers.CharField(source='get_medical_council_display', read_only=True)
    role_display = serializers.CharField(source='get_role_display', read_only=True)

    class Meta:
        model = MedicalProfessional
        fields = [
            'id', 'firebase_uid', 'phone', 'full_name', 'email',
            'role', 'role_display', 'medical_council', 'council_display',
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


class MedicalProfessionalUpdateSerializer(serializers.ModelSerializer):
    """Editable fields only — credentials (license, council) are read-only post-submit."""
    class Meta:
        model = MedicalProfessional
        fields = ['about', 'profile_photo', 'years_experience', 'qualification', 'email']


class DeviceTokenSerializer(serializers.ModelSerializer):
    class Meta:
        model = DeviceToken
        fields = ['token', 'platform', 'app_version']
