from django.urls import path

from . import views

urlpatterns = [
    path('send/', views.send_sos, name='sos-send'),
    path('nearby-doctors/', views.nearby_doctors, name='sos-nearby-doctors'),
    path('my-alerts/', views.my_alerts, name='sos-my-alerts'),
    path('<int:pk>/respond/', views.respond_to_sos, name='sos-respond'),
    path('<int:pk>/status/', views.sos_status, name='sos-status'),
    path('<int:pk>/incoming/', views.incoming_sos, name='sos-incoming'),
]
