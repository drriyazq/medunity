from django.urls import path

from . import views

urlpatterns = [
    path('', views.circles, name='circles-list'),
    path('nearby/', views.nearby_circles, name='circles-nearby'),
    path('<int:pk>/', views.circle_detail, name='circle-detail'),
    path('<int:pk>/join/', views.join_circle, name='circle-join'),
    path('<int:pk>/leave/', views.leave_circle, name='circle-leave'),
    path('<int:pk>/kick/<int:member_id>/', views.kick_member, name='circle-kick'),
    path('<int:pk>/posts/', views.posts, name='circle-posts'),
    path('<int:pk>/posts/<int:post_id>/', views.delete_post, name='circle-post-delete'),
    path('<int:pk>/posts/<int:post_id>/comments/', views.comments, name='circle-comments'),
    path('<int:pk>/posts/<int:post_id>/comments/<int:comment_id>/', views.delete_comment, name='circle-comment-delete'),
]
