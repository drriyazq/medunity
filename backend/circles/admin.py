from django.contrib import admin

from .models import Circle, CircleMembership, CirclePost, PostComment


class CircleMembershipInline(admin.TabularInline):
    model = CircleMembership
    extra = 0
    readonly_fields = ('joined_at',)


@admin.register(Circle)
class CircleAdmin(admin.ModelAdmin):
    list_display = ('id', 'name', 'circle_type', 'member_count', 'radius_km', 'is_active', 'created_at')
    list_filter = ('circle_type', 'is_active')
    readonly_fields = ('member_count', 'created_at')
    inlines = [CircleMembershipInline]


@admin.register(CirclePost)
class CirclePostAdmin(admin.ModelAdmin):
    list_display = ('id', 'circle', 'author', 'post_type', 'is_deleted', 'created_at')
    list_filter = ('post_type', 'is_deleted')
    readonly_fields = ('comment_count', 'created_at', 'updated_at')


@admin.register(PostComment)
class PostCommentAdmin(admin.ModelAdmin):
    list_display = ('id', 'post', 'author', 'is_deleted', 'created_at')
    list_filter = ('is_deleted',)
    readonly_fields = ('created_at',)
