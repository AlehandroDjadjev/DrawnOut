from django.contrib import admin
from .models import MarketItem, MarketListing, TradeProposal, PurchaseHistory

admin.site.register(MarketItem)
admin.site.register(MarketListing)
admin.site.register(TradeProposal)
admin.site.register(PurchaseHistory)
