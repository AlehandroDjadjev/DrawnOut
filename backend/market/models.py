from django.db import models

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

    def __str__(self):
        return f"Listing for {self.item.name} at {self.listed_at} by {self.seller.username}"
    
class TradeProposal(models.Model):
    listing = models.ForeignKey(MarketListing, on_delete=models.CASCADE, related_name="proposals")
    buyer = models.ForeignKey('users.CustomUser', on_delete=models.CASCADE, related_name="sent_proposals")
    proposed_price = models.IntegerField()
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
    price = models.IntegerField()
    purchased_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.buyer} bought {self.item} for {self.price}"
    