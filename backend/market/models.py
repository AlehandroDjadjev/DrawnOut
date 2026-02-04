from django.db import models
from decimal import Decimal

# Create your models here.
class MarketItem(models.Model):
    name = models.CharField(max_length=255)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    stock = models.IntegerField()

    def __str__(self):
        return self.name
    
class MarketListing(models.Model):
    item = models.ForeignKey(MarketItem, on_delete=models.CASCADE)
    listed_at = models.DateTimeField(auto_now_add=True)
    status = models.CharField(max_length=50, choices=[('available', 'Available'), ('sold', 'Sold')], default='available')
    seller = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE)
    quantity = models.IntegerField(default=1)

    def __str__(self):
        return f"Listing for {self.item.name} at {self.listed_at} by {self.seller.username}"
    
class TradeProposal(models.Model):
    listing = models.ForeignKey(MarketListing, on_delete=models.CASCADE, related_name="proposals")
    buyer = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name="sent_proposals")
    proposed_price = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(
        max_length=20,
        choices=[("pending", "Pending"), ("accepted", "Accepted"), ("declined", "Declined")],
        default="pending"
    )
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Proposal {self.proposed_price} for {self.listing.id}"
    
class PurchaseHistory(models.Model):
    buyer = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name="purchases")
    seller = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name="sales")
    item = models.ForeignKey(MarketItem, on_delete=models.SET_NULL, null=True)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    purchased_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.buyer} bought {self.item} for {self.price}"

class Notification(models.Model):
    recipient = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name='notifications')
    actor = models.ForeignKey('users.CustomUser', on_delete=models.SET_NULL, null=True, blank=True, related_name='acted_notifications')
    verb = models.CharField(max_length=255)
    listing = models.ForeignKey(MarketListing, on_delete=models.SET_NULL, null=True, blank=True)
    proposal = models.ForeignKey(TradeProposal, on_delete=models.SET_NULL, null=True, blank=True)
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Notification to {self.recipient} - {self.verb}"

class CounterOffer(models.Model):
    original_proposal = models.ForeignKey(TradeProposal, on_delete=models.CASCADE, related_name='counters')
    from_user = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name='sent_counters')
    to_user = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name='received_counters')
    price = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=[('pending','Pending'),('accepted','Accepted'),('declined','Declined')], default='pending')
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"Counter {self.price} from {self.from_user} to {self.to_user} (orig {self.original_proposal.id})"
    
class OwnedItem(models.Model):
    user = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name='owned_items_relation')
    item = models.ForeignKey(MarketItem, on_delete=models.CASCADE)
    quantity = models.IntegerField(default=0)

    class Meta:
        unique_together = ('user', 'item')

    def __str__(self):
        return f"{self.user.username} owns {self.quantity}x {self.item.name}"
