from django.urls import path
from . import views

urlpatterns = [
    path('search/', views.search_images, name='image_research_search'),
    path('sources/', views.list_sources, name='image_research_sources'),
    path('subjects/', views.get_subjects, name='image_research_subjects'),
    path('ddg-search/', views.search_duckduckgo, name='image_research_ddg'),
]



