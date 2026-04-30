from django.urls import path

from . import views

urlpatterns = [
    path('', views.vendors, name='vendors-list'),
    path('search/', views.search_vendors, name='vendors-search'),
    path('<int:pk>/', views.vendor_detail, name='vendor-detail'),
    path('<int:pk>/review/', views.review_vendor, name='vendor-review'),
    path('<int:pk>/flag/', views.flag_vendor, name='vendor-flag'),
]
