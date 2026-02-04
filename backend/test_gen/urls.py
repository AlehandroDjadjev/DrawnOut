from django.urls import path
from .views import generate_test_api

urlpatterns = [
    path("generate-test/", generate_test_api),
]