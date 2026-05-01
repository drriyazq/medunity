from django.urls import path

from . import views

urlpatterns = [
    path("firebase/", views.firebase_auth_view, name="firebase_auth"),
    path("otp/send/", views.send_otp_view, name="send_otp"),
    path("otp/verify/", views.verify_otp_view, name="verify_otp"),
    path("profile/", views.create_profile, name="create_profile"),
    path("me/", views.me, name="me"),
    path("me/clinic-location/", views.set_clinic_location, name="set_clinic_location"),
    path("verification-status/", views.verification_status, name="verification_status"),
    path("devices/register/", views.register_device, name="register_device"),
    path("devices/unregister/", views.unregister_device, name="unregister_device"),
]
