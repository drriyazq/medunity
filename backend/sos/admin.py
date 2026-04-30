from django.contrib import admin

from .models import SosAlert, SosResponse


class SosResponseInline(admin.TabularInline):
    model = SosResponse
    extra = 0
    readonly_fields = ('responder', 'status', 'responder_lat', 'responder_lng', 'responded_at')


@admin.register(SosAlert)
class SosAlertAdmin(admin.ModelAdmin):
    list_display = ('id', 'sender', 'category', 'radius_km', 'recipient_count', 'status', 'created_at')
    list_filter = ('category', 'status')
    readonly_fields = ('created_at', 'expires_at', 'recipient_count')
    inlines = [SosResponseInline]

    actions = ['mark_resolved']

    @admin.action(description='Mark selected alerts as resolved')
    def mark_resolved(self, request, queryset):
        queryset.update(status='resolved')


@admin.register(SosResponse)
class SosResponseAdmin(admin.ModelAdmin):
    list_display = ('id', 'alert', 'responder', 'status', 'responded_at')
    list_filter = ('status',)
    readonly_fields = ('responded_at',)
