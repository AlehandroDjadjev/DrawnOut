from django.urls import path
from . import views

app_name = "wb_vectorize"

urlpatterns = [
    path("vectorize/", views.vectorize_image, name="vectorize"),
]
