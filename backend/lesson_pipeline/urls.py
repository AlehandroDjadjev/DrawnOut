from django.urls import path
from . import views

urlpatterns = [
    path('generate/', views.generate_lesson_view, name='lesson_pipeline_generate'),
    path('health/', views.health_check, name='lesson_pipeline_health'),
    path('image-proxy/', views.image_proxy_view, name='lesson_pipeline_image_proxy'),
]


