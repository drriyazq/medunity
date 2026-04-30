from django.urls import path

from . import views

urlpatterns = [
    path('requests/', views.requests, name='support-requests'),
    path('requests/mine/', views.my_requests, name='support-my-requests'),
    path('requests/<int:pk>/', views.request_detail, name='support-request-detail'),
    path('requests/<int:pk>/accept/', views.accept_request, name='support-accept'),
    path('requests/<int:pk>/close/', views.close_request, name='support-close'),
    path('leaderboard/', views.leaderboard, name='support-leaderboard'),
    path('my-points/', views.my_points, name='support-my-points'),
]
