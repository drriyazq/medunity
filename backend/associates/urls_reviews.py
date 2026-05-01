"""Mounted at /api/v1/reviews/ — global doctor-to-doctor reviews."""
from django.urls import path

from . import views

urlpatterns = [
    path('', views.submit_review, name='review-submit'),
    path('<int:pk>/', views.delete_review, name='review-delete'),
    path('of/<int:prof_id>/', views.reviews_for, name='reviews-for'),
    path('mine/of/<int:prof_id>/', views.my_review_for, name='reviews-mine-for'),
]
