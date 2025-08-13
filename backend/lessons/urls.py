from django.urls import path
from django.views.decorators.csrf import csrf_exempt
from .views import StartLessonView, NextSegmentView, RaiseHandView, SessionDetailView, LessonCreateView, LessonGetView


urlpatterns = [
    path('start/', csrf_exempt(StartLessonView.as_view()), name='lesson-start'),
    path('<int:session_id>/next/', csrf_exempt(NextSegmentView.as_view()), name='lesson-next'),
    path('<int:session_id>/raise-hand/', csrf_exempt(RaiseHandView.as_view()), name='lesson-raise-hand'),
    path('<int:session_id>/', SessionDetailView.as_view(), name='lesson-session-detail'),
    path('lesson-create/', LessonCreateView.as_view(), name='lesson-create'),
    path('lesson/<int:lesson_id>', LessonGetView.as_view(), name='lesson-get')
]


