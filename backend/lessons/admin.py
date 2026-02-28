from django.contrib import admin

from .models import Lesson, LessonProgress

@admin.register(Lesson)
class LessonAdmin(admin.ModelAdmin):
	list_display = ('id', 'title', 'subject', 'difficulty')
	list_filter = ('subject', 'difficulty')
	search_fields = ('title',)


@admin.register(LessonProgress)
class LessonProgressAdmin(admin.ModelAdmin):
	list_display = ('id', 'user', 'lesson', 'state', 'started_at', 'completed_at', 'updated_at')
	list_filter = ('state',)
	search_fields = ('user__username', 'lesson__title')