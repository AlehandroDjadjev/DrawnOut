from rest_framework import serializers
from .models import LessonSession, Utterance


class UtteranceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Utterance
        fields = ['id', 'role', 'text', 'audio_file', 'created_at']


class LessonSessionSerializer(serializers.ModelSerializer):
    utterances = UtteranceSerializer(many=True, read_only=True)

    class Meta:
        model = LessonSession
        fields = [
            'id', 'user', 'topic', 'lesson_plan', 'current_step_index',
            'is_waiting_for_question', 'is_completed', 'created_at', 'updated_at',
            'utterances'
        ]
        read_only_fields = ['user', 'created_at', 'updated_at']


