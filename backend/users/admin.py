from django.contrib import admin
from .models import CustomUser, ProfilePictures

admin.site.register(CustomUser)
admin.site.register(ProfilePictures)
