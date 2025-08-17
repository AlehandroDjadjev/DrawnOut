from django.contrib import admin
from .models import CustomUser, ProfilePicture

admin.site.register(CustomUser)
admin.site.register(ProfilePicture)
