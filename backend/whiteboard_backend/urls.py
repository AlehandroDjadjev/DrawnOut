from django.urls import path

from . import views

app_name = "whiteboard_backend"

urlpatterns = [
    path("image-pipeline/", views.run_image_pipeline, name="image_pipeline"),
    # Font glyph API
    path("font/metrics/", views.get_font_metrics, name="font_metrics"),
    path("font/glyph/<str:hex_code>/", views.get_font_glyph, name="font_glyph"),
]
