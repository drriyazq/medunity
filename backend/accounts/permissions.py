from rest_framework import permissions


class IsAdminVerified(permissions.BasePermission):
    """
    Allows access only to users whose MedicalProfessional profile is
    admin-verified AND active. Used as default permission for all Phase 2+
    endpoints. Belt-and-braces: list views also filter by is_admin_verified=True.
    """

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        prof = getattr(request.user, 'professional', None)
        return bool(prof and prof.is_admin_verified and prof.is_active_listing)
