from django.urls import path

from . import views

urlpatterns = [
    path('availability/', views.my_availability, name='consultant-availability'),
    path('me/location/', views.update_location, name='consultant-update-location'),
    path('me/settings/', views.my_settings, name='consultant-settings'),
    path('me/blocklist/', views.my_blocklist, name='consultant-blocklist'),
    path('me/allowlist/', views.my_allowlist, name='consultant-allowlist'),
    path('lookup-by-phone/', views.lookup_by_phone, name='consultant-lookup-phone'),
    path('nearby/', views.nearby_consultants, name='consultants-nearby'),
    path('profile/<int:prof_id>/', views.consultant_profile, name='consultant-profile'),
    path('bookings/', views.bookings, name='consultant-bookings'),
    path('bookings/<int:pk>/decline-and-block/',
         views.decline_and_block, name='booking-decline-block'),
    path('bookings/<int:pk>/<str:action>/', views.booking_action, name='booking-action'),
    path('bookings/<int:pk>/review/', views.submit_review, name='booking-review'),
]
