from django.db import models
from django.conf import settings


class LessonSession(models.Model):
    """Represents a single AI-tutored lesson session."""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='lesson_sessions', null=True, blank=True)
    # Optional link to a Lesson definition (used for progress/status on lesson cards).
    lesson = models.ForeignKey('Lesson', on_delete=models.SET_NULL, null=True, blank=True, related_name='sessions')
    topic = models.CharField(max_length=255)
    lesson_plan = models.JSONField(default=list)
    current_step_index = models.PositiveIntegerField(default=0)
    is_waiting_for_question = models.BooleanField(default=False)
    is_completed = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def progress_state(self) -> str:
        """Returns one of: not_started / in_progress / completed.

        For sessions, the state is always at least in_progress (it exists).
        """
        return 'completed' if self.is_completed else 'in_progress'


class Utterance(models.Model):
    """Stores the tutor's spoken segments and associated audio files."""
    session = models.ForeignKey(LessonSession, on_delete=models.CASCADE, related_name='utterances')
    role = models.CharField(max_length=16, choices=(('tutor', 'tutor'), ('student', 'student')))
    text = models.TextField()
    audio_file = models.FileField(upload_to='tts/', null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

class Lesson(models.Model):
    SUBJECT_CHOICES = (
        ('mathematics', 'Mathematics'),
        ('physics', 'Physics'),
        ('biology', 'Biology'),
        ('chemistry', 'Chemistry'),
        ('computer_science', 'Computer Science'),
        ('other', 'Other'),
    )

    DIFFICULTY_CHOICES = (
        ('beginner', 'Beginner'),
        ('intermediate', 'Intermediate'),
        ('advanced', 'Advanced'),
    )

    title = models.CharField(max_length=50)
    subject = models.CharField(
        max_length=32,
        choices=SUBJECT_CHOICES,
        default='mathematics',
    )
    difficulty = models.CharField(
        max_length=16,
        choices=DIFFICULTY_CHOICES,
        default='beginner',
    )
    plan = models.TextField()
    thumbnail = models.ImageField(upload_to="thumbnails/")

    def __str__(self) -> str:
        return self.title


class LessonProgress(models.Model):
    class State(models.TextChoices):
        NOT_STARTED = 'not_started', 'Not started'
        IN_PROGRESS = 'in_progress', 'In progress'
        COMPLETED = 'completed', 'Completed'

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='lesson_progress',
    )
    lesson = models.ForeignKey(
        Lesson,
        on_delete=models.CASCADE,
        related_name='progress_records',
    )
    state = models.CharField(
        max_length=16,
        choices=State.choices,
        default=State.NOT_STARTED,
    )
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('user', 'lesson')
        indexes = [
            models.Index(fields=['user', 'lesson']),
            models.Index(fields=['user', 'state']),
        ]

    def __str__(self) -> str:
        return f'{self.user_id}:{self.lesson_id}:{self.state}'


