from django.db import models
from lessons.models import LessonSession


class Timeline(models.Model):
    """Stores a generated synchronized timeline"""
    session = models.ForeignKey(
        LessonSession, 
        on_delete=models.CASCADE, 
        related_name='timelines'
    )
    segments = models.JSONField()  # List of timeline segments
    total_duration = models.FloatField()
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-created_at']
    
    def __str__(self):
        return f"Timeline {self.id} for session {self.session_id}"


class TimelineSegment(models.Model):
    """Individual segment of a timeline"""
    timeline = models.ForeignKey(
        Timeline, 
        on_delete=models.CASCADE, 
        related_name='segment_records'
    )
    sequence_number = models.IntegerField()
    start_time = models.FloatField()  # seconds
    end_time = models.FloatField()  # seconds
    speech_text = models.TextField()
    audio_file = models.FileField(
        upload_to='timeline_audio/', 
        null=True, 
        blank=True
    )
    actual_audio_duration = models.FloatField(null=True, blank=True)
    drawing_actions = models.JSONField()  # Whiteboard actions for this segment
    
    class Meta:
        ordering = ['sequence_number']
        unique_together = ['timeline', 'sequence_number']
    
    def __str__(self):
        return f"Segment {self.sequence_number} of Timeline {self.timeline_id}"





