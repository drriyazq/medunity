from django.contrib import admin
from django.utils import timezone
from django.utils.html import format_html

from .models import Clinic, DeviceToken, MedicalProfessional
from .tasks import notify_verification_decision


class ClinicInline(admin.StackedInline):
    model = Clinic
    extra = 0
    readonly_fields = ['location_set_at', 'created_at', 'updated_at']
    fields = ['name', 'address', 'city', 'state', 'pincode', 'phone',
              'landline_phone', 'website', 'lat', 'lng', 'location_set_at']


@admin.register(MedicalProfessional)
class MedicalProfessionalAdmin(admin.ModelAdmin):
    list_display = [
        'full_name', 'phone', 'specialization', 'role', 'medical_council',
        'verification_badge', 'is_active_listing', 'verification_submitted_at',
    ]
    list_filter = ['is_admin_verified', 'is_active_listing', 'role', 'specialization', 'medical_council']
    search_fields = ['full_name', 'phone', 'license_number', 'user__username']
    readonly_fields = [
        'firebase_uid', 'verification_submitted_at', 'verified_at',
        'verified_by', 'created_at', 'updated_at',
        'license_doc_preview', 'degree_doc_preview',
    ]
    inlines = [ClinicInline]
    actions = ['mark_verified', 'mark_rejected', 'deactivate_listing']

    fieldsets = (
        ('Identity', {
            'fields': ('user', 'firebase_uid', 'full_name', 'phone', 'email', 'profile_photo'),
        }),
        ('Professional', {
            'fields': ('role', 'specialization', 'medical_council', 'license_number',
                       'years_experience', 'qualification', 'about'),
        }),
        ('Documents', {
            'fields': ('license_doc', 'license_doc_preview', 'degree_doc', 'degree_doc_preview',
                       'clinic_proof_doc'),
        }),
        ('Verification Gate', {
            'fields': ('is_admin_verified', 'is_active_listing', 'rejection_reason',
                       'verification_submitted_at', 'verified_at', 'verified_by', 'admin_notes'),
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',),
        }),
    )

    def verification_badge(self, obj):
        if obj.is_admin_verified:
            return format_html('<span style="color:green;font-weight:bold">✓ Verified</span>')
        if obj.rejection_reason:
            return format_html('<span style="color:red">✗ Rejected</span>')
        return format_html('<span style="color:orange">⏳ Pending</span>')
    verification_badge.short_description = 'Status'

    def license_doc_preview(self, obj):
        if obj.license_doc:
            return format_html('<a href="{}" target="_blank">View License Doc</a>', obj.license_doc.url)
        return '—'
    license_doc_preview.short_description = 'License Document'

    def degree_doc_preview(self, obj):
        if obj.degree_doc:
            return format_html('<a href="{}" target="_blank">View Degree Doc</a>', obj.degree_doc.url)
        return '—'
    degree_doc_preview.short_description = 'Degree Document'

    @admin.action(description='✓ Mark selected as Verified')
    def mark_verified(self, request, queryset):
        count = 0
        for prof in queryset.filter(is_admin_verified=False):
            prof.is_admin_verified = True
            prof.verified_at = timezone.now()
            prof.verified_by = request.user
            prof.rejection_reason = ''
            prof.save(update_fields=['is_admin_verified', 'verified_at', 'verified_by', 'rejection_reason'])
            notify_verification_decision.delay(prof.pk, 'verified')
            count += 1
        self.message_user(request, f"{count} professional(s) verified.")

    @admin.action(description='✗ Mark selected as Rejected')
    def mark_rejected(self, request, queryset):
        count = 0
        for prof in queryset.filter(is_admin_verified=False):
            prof.rejection_reason = 'Your documents could not be verified. Please resubmit with clear, valid documents.'
            prof.is_admin_verified = False
            prof.save(update_fields=['is_admin_verified', 'rejection_reason'])
            notify_verification_decision.delay(prof.pk, 'rejected')
            count += 1
        self.message_user(request, f"{count} professional(s) rejected.")

    @admin.action(description='Deactivate listing (hide from network)')
    def deactivate_listing(self, request, queryset):
        updated = queryset.update(is_active_listing=False)
        self.message_user(request, f"{updated} listing(s) deactivated.")


@admin.register(Clinic)
class ClinicAdmin(admin.ModelAdmin):
    list_display = ['name', 'owner', 'city', 'state', 'phone', 'lat', 'lng']
    search_fields = ['name', 'city', 'owner__full_name']
    list_filter = ['state']
    readonly_fields = ['location_set_at', 'created_at', 'updated_at']


@admin.register(DeviceToken)
class DeviceTokenAdmin(admin.ModelAdmin):
    list_display = ['user', 'platform', 'app_version', 'last_seen_at']
    search_fields = ['user__username', 'token']
    list_filter = ['platform']
    readonly_fields = ['last_seen_at', 'created_at']
