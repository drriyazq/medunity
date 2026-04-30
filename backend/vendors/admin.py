from django.contrib import admin

from .models import Vendor, VendorFlag, VendorReview


class VendorReviewInline(admin.TabularInline):
    model = VendorReview
    extra = 0
    readonly_fields = ('reviewer', 'rating', 'quality_rating', 'delivery_rating', 'created_at')


class VendorFlagInline(admin.TabularInline):
    model = VendorFlag
    extra = 0
    readonly_fields = ('reporter', 'reason', 'details', 'created_at')


@admin.register(Vendor)
class VendorAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'category', 'city', 'avg_rating', 'review_count',
                    'flag_count', 'is_verified', 'created_at')
    list_filter = ('category', 'is_verified')
    search_fields = ('name', 'city')
    readonly_fields = ('avg_rating', 'avg_quality', 'avg_delivery', 'review_count',
                       'flag_count', 'created_at', 'updated_at')
    actions = ['verify_vendors', 'hide_flagged']
    inlines = [VendorReviewInline, VendorFlagInline]

    @admin.action(description='Mark selected as verified')
    def verify_vendors(self, request, queryset):
        queryset.update(is_verified=True)

    @admin.action(description='Hide flagged (set flag_count = 5)')
    def hide_flagged(self, request, queryset):
        queryset.update(flag_count=5)
