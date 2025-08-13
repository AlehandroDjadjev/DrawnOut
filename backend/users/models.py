from django.db import models
from django.contrib.auth.models import AbstractUser


class CustomUser(AbstractUser):
    pfp = models.ImageField(blank=True, null=True, upload_to="profile_pictires/")