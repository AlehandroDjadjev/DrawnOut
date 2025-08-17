from django.db import models
from django.contrib.auth.models import AbstractUser

class ProfilePicture(models.Model):
    image = models.ImageField(upload_to="profile_pictures/")
    price = models.IntegerField(default=0)

class CustomUser(AbstractUser):
    credits = models.IntegerField(default=0)
    owned_pictures = models.ManyToManyField(ProfilePicture, blank=True)
    current_pfp = models.ForeignKey(ProfilePicture, on_delete=models.SET_NULL, null=True, blank=True, related_name='current_for')