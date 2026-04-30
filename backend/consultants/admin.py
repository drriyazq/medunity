from django.contrib import admin

from .models import ConsultantAvailability, ConsultantBooking, ConsultantReview


@admin.register(ConsultantAvailability)
class ConsultantAvailabilityAdmin(admin.ModelAdmin):
    list_display = ('consultant', 'is_available', 'available_since', 'updated_at')
    list_filter = ('is_available',)
    readonly_fields = ('updated_at',)


class ConsultantReviewInline(admin.TabularInline):
    model = ConsultantReview
    extra = 0
    readonly_fields = ('reviewer', 'reviewee', 'rating', 'created_at')


@admin.register(ConsultantBooking)
class ConsultantBookingAdmin(admin.ModelAdmin):
    list_display = ('id', 'requester', 'consultant', 'procedure', 'status', 'requested_at')
    list_filter = ('status',)
    readonly_fields = ('requested_at', 'responded_at', 'completed_at')
    inlines = [ConsultantReviewInline]


@admin.register(ConsultantReview)
class ConsultantReviewAdmin(admin.ModelAdmin):
    list_display = ('id', 'reviewer', 'reviewee', 'rating', 'created_at')
    list_filter = ('rating',)
    readonly_fields = ('created_at',)
