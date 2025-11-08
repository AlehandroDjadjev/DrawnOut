# vision/urls.py
from django.urls import path

from .views import Siglip2ZeroShotView, Siglip2EmbeddingView

urlpatterns = [
    path("zero-shot/", Siglip2ZeroShotView.as_view(), name="siglip2-zero-shot"),
    path("embed/", Siglip2EmbeddingView.as_view(), name="siglip2-embed"),
]


