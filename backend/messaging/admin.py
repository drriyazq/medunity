from django.contrib import admin

from .models import DirectMessage, DirectThread, ThreadReadState


@admin.register(DirectThread)
class DirectThreadAdmin(admin.ModelAdmin):
    list_display = ('id', 'participant_a', 'participant_b', 'last_message_at', 'created_at')
    list_select_related = ('participant_a', 'participant_b')
    search_fields = ('participant_a__user__username', 'participant_b__user__username')


@admin.register(DirectMessage)
class DirectMessageAdmin(admin.ModelAdmin):
    list_display = ('id', 'thread', 'sender', 'created_at', 'short_body')
    list_select_related = ('thread', 'sender')
    list_filter = ('created_at',)

    def short_body(self, obj):
        return (obj.body[:80] + '…') if len(obj.body) > 80 else obj.body


@admin.register(ThreadReadState)
class ThreadReadStateAdmin(admin.ModelAdmin):
    list_display = ('thread', 'professional', 'last_read_at')
    list_select_related = ('thread', 'professional')
