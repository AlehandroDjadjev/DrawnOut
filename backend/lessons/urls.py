from django.urls import path
from django.views.decorators.csrf import csrf_exempt
from .views import StartLessonView, NextSegmentView, RaiseHandView, SessionDetailView, LessonGetView, LessonsListView, LiveChatView, LiveSDPView, LiveTokenView, DiagnosticsView, DiagramView


urlpatterns = [
    path('start/', csrf_exempt(StartLessonView.as_view()), name='lesson-start'),
    path('<int:session_id>/next/', csrf_exempt(NextSegmentView.as_view()), name='lesson-next'),
    path('<int:session_id>/raise-hand/', csrf_exempt(RaiseHandView.as_view()), name='lesson-raise-hand'),
    path('<int:session_id>/', SessionDetailView.as_view(), name='lesson-session-detail'),
    path('<int:session_id>/sdp/', csrf_exempt(LiveSDPView.as_view()), name='lesson-live-sdp'),
    path('<int:session_id>/live/', csrf_exempt(LiveChatView.as_view()), name='lesson-live'),
    path('token/', csrf_exempt(LiveTokenView.as_view()), name='lesson-live-token'),
    path('diagnostics/', csrf_exempt(DiagnosticsView.as_view()), name='lesson-diagnostics'),
    path('diagram/', csrf_exempt(DiagramView.as_view()), name='lesson-diagram'),
    path('lesson/<int:lesson_id>', LessonGetView.as_view(), name='lesson-get'),
    path('list/', LessonsListView.as_view(), name='lessons-list'),
]