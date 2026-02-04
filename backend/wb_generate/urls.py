from django.urls import path
from . import views

app_name = "wb_generate"

urlpatterns = [
    path("generate/", views.generate_image, name="generate"),
    path("font/<str:char_hex>.json", views.get_font_glyph, name="font_glyph"),
]












