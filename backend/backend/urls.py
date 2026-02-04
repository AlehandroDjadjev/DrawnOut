"""
URL configuration for backend project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.1/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from django.views.generic import TemplateView
from django.conf import settings
from django.conf.urls.static import static
from TTSVoice import tts

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/auth/', include('users.urls')),
    path('api/lessons/', include('lessons.urls')),
    path('api/timeline/', include('timeline_generator.urls')),
    path('api/lesson-pipeline/', include('lesson_pipeline.urls')),
    path('api/wb/research/', include('wb_research.urls')),
    path('api/wb/preprocess/', include('wb_preprocess.urls')),
    path('api/wb/vectorize/', include('wb_vectorize.urls')),
    path('api/wb/generate/', include('wb_generate.urls')),
    path('api/vision/', include('vision.urls')),  # SigLIP2 endpoints
    path('api/market/', include('market.urls')),
    path('', TemplateView.as_view(template_name='canvasapp/index.html'), name='index'),
    path('tts-demo/', TemplateView.as_view(template_name='canvasapp/tts-demo.html'), name='tts_demo'),
    path('api/tests/', include('test_gen.urls')),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
