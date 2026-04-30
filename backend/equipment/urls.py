from django.urls import path

from . import views

urlpatterns = [
    # Pools
    path('pools/', views.pools, name='equipment-pools'),
    path('pools/<int:pk>/', views.pool_detail, name='pool-detail'),
    path('pools/<int:pk>/join/', views.join_pool, name='pool-join'),
    path('pools/<int:pk>/leave/', views.leave_pool, name='pool-leave'),
    path('pools/<int:pk>/status/', views.update_pool_status, name='pool-status'),
    path('pools/<int:pk>/slots/', views.pool_slots, name='pool-slots'),
    path('pools/<int:pk>/slots/<int:slot_id>/', views.cancel_slot, name='pool-slot-cancel'),
    # Marketplace
    path('listings/', views.listings, name='equipment-listings'),
    path('listings/mine/', views.my_listings, name='my-listings'),
    path('listings/<int:pk>/', views.listing_detail, name='listing-detail'),
    path('listings/<int:pk>/inquire/', views.inquire, name='listing-inquire'),
]
