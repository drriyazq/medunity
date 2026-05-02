from rest_framework import serializers

from .models import AssociateBooking, AssociateProfile, ProfessionalReview


class ProfessionalMiniSerializer(serializers.Serializer):
    """Public-facing snippet of a doctor — never includes the reviewer chain."""
    id = serializers.IntegerField()
    full_name = serializers.CharField()
    specialization_display = serializers.CharField(source='get_specialization_display')
    profile_photo = serializers.SerializerMethodField()

    def get_profile_photo(self, obj):
        return obj.profile_photo.url if obj.profile_photo else None


class AssociateProfileSerializer(serializers.ModelSerializer):
    full_name = serializers.CharField(source='professional.full_name', read_only=True)
    phone = serializers.CharField(source='professional.phone', read_only=True)
    specialization_display = serializers.CharField(
        source='professional.get_specialization_display', read_only=True
    )
    professional_id = serializers.IntegerField(source='professional.id', read_only=True)

    class Meta:
        model = AssociateProfile
        fields = [
            'professional_id', 'full_name', 'phone', 'specialization_display',
            'is_available_for_hire', 'bio', 'slot_hours',
            'rate_per_slot', 'rate_per_day',
            'base_lat', 'base_lng', 'base_locality', 'base_city', 'base_state',
            'travel_radius_km', 'notes',
            'created_at', 'updated_at',
        ]
        read_only_fields = ['created_at', 'updated_at']

    def validate(self, attrs):
        # When marking available, at least one rate must be set.
        new_avail = attrs.get('is_available_for_hire',
                              self.instance.is_available_for_hire if self.instance else False)
        new_slot = attrs.get('rate_per_slot',
                             self.instance.rate_per_slot if self.instance else None)
        new_day = attrs.get('rate_per_day',
                            self.instance.rate_per_day if self.instance else None)
        if new_avail and not (new_slot or new_day):
            raise serializers.ValidationError(
                'Set at least one of rate_per_slot or rate_per_day before going live.'
            )
        return attrs


class AssociateBookingSerializer(serializers.ModelSerializer):
    associate_name = serializers.CharField(source='associate.full_name', read_only=True)
    associate_phone = serializers.SerializerMethodField()
    associate_specialization = serializers.CharField(
        source='associate.get_specialization_display', read_only=True
    )
    hiring_clinic_name = serializers.CharField(source='hiring_clinic.full_name', read_only=True)
    hiring_clinic_phone = serializers.SerializerMethodField()
    hiring_clinic_label = serializers.SerializerMethodField()
    slot_kind_display = serializers.CharField(source='get_slot_kind_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = AssociateBooking
        fields = [
            'id', 'associate', 'associate_name', 'associate_phone',
            'associate_specialization',
            'hiring_clinic', 'hiring_clinic_name', 'hiring_clinic_phone',
            'hiring_clinic_label',
            'proposed_start', 'proposed_end', 'slot_kind', 'slot_kind_display',
            'rate_quoted', 'notes', 'status', 'status_display',
            'cancelled_by', 'cancel_reason',
            'requested_at', 'responded_at',
        ]
        read_only_fields = [
            'id', 'associate_name', 'associate_phone', 'associate_specialization',
            'hiring_clinic', 'hiring_clinic_name', 'hiring_clinic_phone',
            'hiring_clinic_label', 'rate_quoted', 'status_display',
            'requested_at', 'responded_at',
        ]

    def _phone_visible(self, obj):
        # Phone numbers are revealed only after both parties are connected.
        return obj.status == 'connected'

    def get_associate_phone(self, obj):
        return obj.associate.phone if self._phone_visible(obj) else ''

    def get_hiring_clinic_phone(self, obj):
        return obj.hiring_clinic.phone if self._phone_visible(obj) else ''

    def get_hiring_clinic_label(self, obj):
        clinic = getattr(obj.hiring_clinic, 'clinic', None)
        return clinic.name if clinic else obj.hiring_clinic.full_name


class ProfessionalReviewSerializer(serializers.ModelSerializer):
    """Public review payload — `reviewer` field intentionally absent."""
    context_display = serializers.CharField(source='get_context_display', read_only=True)

    class Meta:
        model = ProfessionalReview
        fields = ['id', 'reviewee', 'rating', 'comment', 'context',
                  'context_display', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at', 'context_display']
