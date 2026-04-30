from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("api.urls")),
    path("api/v1/auth/", include("accounts.urls")),
    path("api/v1/sos/", include("sos.urls")),
    path("api/v1/circles/", include("circles.urls")),
    path("api/v1/consultants/", include("consultants.urls")),
    path("api/v1/equipment/", include("equipment.urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
