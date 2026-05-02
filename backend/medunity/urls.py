from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    # Mounted at /medunity-admin/ (not /admin/) so that admin-generated URLs
    # match the public path under https://trusmiledentist.in/medunity-admin/
    # and don't collide with the cross-project hub at trusmiledentist.in/admin/.
    path("medunity-admin/", admin.site.urls),
    path("api/v1/", include("api.urls")),
    path("api/v1/auth/", include("accounts.urls")),
    path("api/v1/sos/", include("sos.urls")),
    path("api/v1/circles/", include("circles.urls")),
    path("api/v1/consultants/", include("consultants.urls")),
    path("api/v1/equipment/", include("equipment.urls")),
    path("api/v1/support/", include("support.urls")),
    path("api/v1/vendors/", include("vendors.urls")),
    path("api/v1/associates/", include("associates.urls")),
    path("api/v1/reviews/", include("associates.urls_reviews")),
    path("api/v1/messages/", include("messaging.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
