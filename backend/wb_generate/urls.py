from django.urls import path
from . import views

app_name = "wb_generate"

urlpatterns = [
    path("generate/", views.generate_image, name="generate"),
]












