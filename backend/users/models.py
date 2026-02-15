from django.db import models
from django.contrib.auth.models import AbstractUser
from market.models import MarketItem

class Avatar(models.Model):
    image = models.ImageField(upload_to="profile_pictures/")
    price = models.IntegerField(default=0)

class CustomUser(AbstractUser):
    credits = models.IntegerField(default=0)
    owned_avatars = models.ManyToManyField(Avatar, blank=True)
    avatar = models.ForeignKey(Avatar, on_delete=models.SET_NULL, null=True, blank=True, related_name='current_for')
    inventory = models.ManyToManyField(MarketItem, blank=True)
    
    # Developer flag - manually set via admin/database
    # Enables debug panel and advanced features in the app
    is_developer = models.BooleanField(default=False)