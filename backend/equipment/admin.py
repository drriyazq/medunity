from django.contrib import admin

from .models import EquipmentPool, ListingInquiry, MarketplaceListing, PoolMembership, PoolUsageSlot


class PoolMembershipInline(admin.TabularInline):
    model = PoolMembership
    extra = 0
    readonly_fields = ('joined_at',)


class PoolUsageSlotInline(admin.TabularInline):
    model = PoolUsageSlot
    extra = 0
    readonly_fields = ('created_at',)


@admin.register(EquipmentPool)
class EquipmentPoolAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'category', 'target_amount', 'committed_amount', 'member_count', 'status', 'created_at')
    list_filter = ('category', 'status')
    readonly_fields = ('member_count', 'committed_amount', 'created_at')
    inlines = [PoolMembershipInline, PoolUsageSlotInline]


class ListingInquiryInline(admin.TabularInline):
    model = ListingInquiry
    extra = 0
    readonly_fields = ('created_at',)


@admin.register(MarketplaceListing)
class MarketplaceListingAdmin(admin.ModelAdmin):
    list_display = ('id', 'title', 'category', 'price', 'condition', 'status', 'seller', 'created_at')
    list_filter = ('category', 'status', 'condition')
    readonly_fields = ('inquiry_count', 'created_at', 'updated_at')
    inlines = [ListingInquiryInline]
