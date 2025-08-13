from django.db import models
from django.conf import settings


class LessonSession(models.Model):
    """Represents a single AI-tutored lesson session."""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='lesson_sessions', null=True, blank=True)
    topic = models.CharField(max_length=255)
    lesson_plan = models.JSONField(default=list)
    current_step_index = models.PositiveIntegerField(default=0)
    is_waiting_for_question = models.BooleanField(default=False)
    is_completed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class Utterance(models.Model):
    """Stores the tutor's spoken segments and associated audio files."""
    session = models.ForeignKey(LessonSession, on_delete=models.CASCADE, related_name='utterances')
    role = models.CharField(max_length=16, choices=(('tutor', 'tutor'), ('student', 'student')))
    text = models.TextField()
    audio_file = models.FileField(upload_to='tts/', null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

class Lesson(models.Model):
    title = models.CharField(max_length=50)
    plan = models.TextField()
    thumbnail = models.ImageField(upload_to="thumbnails/")


