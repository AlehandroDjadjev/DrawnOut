"""URL configuration for timeline_generator app - force reload"""
from django.urls import path
from .views import GenerateTimelineView, GetTimelineView, GetSessionTimelineView

urlpatterns = [
    path('generate/<int:session_id>/', GenerateTimelineView.as_view(), name='generate_timeline'),
    path('<int:timeline_id>/', GetTimelineView.as_view(), name='get_timeline'),
    path('session/<int:session_id>/', GetSessionTimelineView.as_view(), name='get_session_timeline'),
]



