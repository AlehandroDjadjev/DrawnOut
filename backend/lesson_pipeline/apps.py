from django.apps import AppConfig


class LessonPipelineConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'lesson_pipeline'
    verbose_name = 'Lesson Generation Pipeline'


