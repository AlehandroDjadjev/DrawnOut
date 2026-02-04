from django.urls import path
from .views import generate_images_batch, research_images, process_images, list_objects, create_image_object, create_text_object, delete_object

urlpatterns = [
    path("generate/", generate_images_batch),  # prompt, path_out
    path("research/", research_images),  # prompt, subj
    path("preprocess/", process_images),  # inputdir, outputdir
    
    # Whiteboard object endpoints (included at /api/whiteboard/)
    path("objects/", list_objects, name="wb-list-objects"),
    path("objects/image/", create_image_object, name="wb-create-image"),
    path("objects/text/", create_text_object, name="wb-create-text"),
    path("objects/delete/", delete_object, name="wb-delete-object"),
]
