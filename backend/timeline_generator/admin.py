from django.contrib import admin
from .models import Timeline, TimelineSegment


@admin.register(Timeline)
class TimelineAdmin(admin.ModelAdmin):
    list_display = ['id', 'session', 'total_duration', 'created_at']
    list_filter = ['created_at']
    search_fields = ['session__topic']
    readonly_fields = ['created_at']


@admin.register(TimelineSegment)
class TimelineSegmentAdmin(admin.ModelAdmin):
    list_display = ['id', 'timeline', 'sequence_number', 'speech_text', 'start_time', 'end_time']
    list_filter = ['timeline']
    search_fields = ['speech_text']
    ordering = ['timeline', 'sequence_number']











