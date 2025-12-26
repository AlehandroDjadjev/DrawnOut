from django.urls import path
from . import views

app_name = "wb_preprocess"

urlpatterns = [
    path("run/", views.run_preprocess, name="run"),
]












