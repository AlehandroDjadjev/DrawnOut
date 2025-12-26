from django.urls import path
from . import views

app_name = "wb_research"

urlpatterns = [
    path("search/", views.search_images, name="search"),
    path("sources/", views.list_sources, name="sources"),
    path("subjects/", views.get_subjects, name="subjects"),
    path("ddg-search/", views.search_duckduckgo, name="ddg_search"),
]


