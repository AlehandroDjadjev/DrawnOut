from rest_framework import serializers
from .models import LessonSession, Utterance, Lesson


class UtteranceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Utterance
        fields = ['id', 'role', 'text', 'audio_file', 'created_at']


class LessonSessionSerializer(serializers.ModelSerializer):
    utterances = UtteranceSerializer(many=True, read_only=True)
    lesson_id = serializers.IntegerField(source='lesson.id', read_only=True)
    progress_state = serializers.CharField(read_only=True)

    class Meta:
        model = LessonSession
        fields = [
            'id', 'user', 'lesson_id', 'topic', 'lesson_plan', 'current_step_index',
            'is_waiting_for_question', 'is_completed', 'use_existing_images',
            'use_elevenlabs_tts',
            'resume_segment_index', 'resume_playback_time',
            'created_at', 'updated_at',
            'progress_state',
            'utterances'
        ]
        read_only_fields = ['user', 'created_at', 'updated_at']

class LessonSerializer(serializers.ModelSerializer):
    class Meta:
        model = Lesson
        fields = ['id', 'title', 'subject', 'difficulty', 'thumbnail', 'plan']

    def create(self, validated_data):
        lesson = Lesson(**validated_data)
        lesson.save()
        return lesson


class LessonWithProgressSerializer(LessonSerializer):
    progress_state = serializers.SerializerMethodField()

    class Meta(LessonSerializer.Meta):
        fields = LessonSerializer.Meta.fields + ['progress_state']

    def get_progress_state(self, obj: Lesson) -> str:
        progress_by_lesson_id = self.context.get('progress_by_lesson_id') or {}
        return progress_by_lesson_id.get(obj.id, 'not_started')

