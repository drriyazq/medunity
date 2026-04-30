from django.urls import path

from . import views

urlpatterns = [
    path('availability/', views.my_availability, name='consultant-availability'),
    path('nearby/', views.nearby_consultants, name='consultants-nearby'),
    path('profile/<int:prof_id>/', views.consultant_profile, name='consultant-profile'),
    path('bookings/', views.bookings, name='consultant-bookings'),
    path('bookings/<int:pk>/<str:action>/', views.booking_action, name='booking-action'),
    path('bookings/<int:pk>/review/', views.submit_review, name='booking-review'),
]
