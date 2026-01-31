from django.contrib import admin
from .models import CustomUser, Avatar

admin.site.register(CustomUser)
admin.site.register(Avatar)
