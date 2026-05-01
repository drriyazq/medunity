from django.urls import path

from . import views

urlpatterns = [
    # Associate marketplace
    path('me/', views.me_associate_profile, name='associate-me'),
    path('me/toggle/', views.me_toggle_availability, name='associate-toggle'),
    path('search/', views.search, name='associate-search'),
    path('bookings/', views.bookings_collection, name='associate-bookings'),
    path('bookings/<int:pk>/', views.booking_detail, name='associate-booking-detail'),
    path('<int:prof_id>/', views.public_profile, name='associate-public-profile'),
]
