from django.contrib import admin

from .models import BrowniePoint, CoverageRequest


@admin.register(CoverageRequest)
class CoverageRequestAdmin(admin.ModelAdmin):
    list_display = ('id', 'request_type', 'title', 'requester', 'accepted_by', 'status', 'city', 'created_at')
    list_filter = ('request_type', 'status')
    readonly_fields = ('created_at', 'accepted_at')
    actions = ['close_selected']

    @admin.action(description='Close selected requests')
    def close_selected(self, request, queryset):
        queryset.update(status='closed')


@admin.register(BrowniePoint)
class BrowniePointAdmin(admin.ModelAdmin):
    list_display = ('id', 'recipient', 'source_type', 'points', 'reason', 'awarded_at')
    list_filter = ('source_type',)
    readonly_fields = ('awarded_at',)
