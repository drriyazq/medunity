from django.urls import path

from . import views

urlpatterns = [
    path('threads/', views.threads, name='msg-threads'),
    path('unread-count/', views.unread_count, name='msg-unread-count'),
    path('threads/with/<int:prof_id>/', views.start_thread_with, name='msg-start'),
    path('threads/<int:pk>/', views.thread_detail, name='msg-thread-detail'),
    path('threads/<int:pk>/messages/', views.send_message, name='msg-send'),
    path('threads/<int:pk>/read/', views.mark_read, name='msg-read'),
    path('threads/<int:pk>/delete/', views.delete_thread, name='msg-delete-thread'),
    path('threads/<int:pk>/messages/<int:msg_id>/delete/',
         views.delete_message, name='msg-delete-message'),
]
