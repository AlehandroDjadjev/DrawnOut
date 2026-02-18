from rest_framework import serializers
from .models import MarketItem, MarketListing, TradeProposal, PurchaseHistory, Notification, CounterOffer, OwnedItem

class MarketListingSerializer(serializers.ModelSerializer):
    item_id = serializers.PrimaryKeyRelatedField(
        queryset=MarketItem.objects.all(),
        write_only=True,
        source="item"
    )
    item_name = serializers.CharField(source="item.name", read_only=True)
    item_stock = serializers.IntegerField(source='item.stock', read_only=True)
    price = serializers.DecimalField(
        source="item.price",
        max_digits=10,
        decimal_places=2,
        read_only=True
    )
    seller_username = serializers.CharField(source="seller.username", read_only=True)

    class Meta:
        model = MarketListing
        fields = [
            "id",
            "item_id",
            "item_name",
            "item_stock",
            "price",
            "listed_at",
            "status",
            "seller_username",
            "quantity",
        ]

class CounterOfferSerializer(serializers.ModelSerializer):
    from_username = serializers.CharField(source='from_user.username', read_only=True)
    to_username = serializers.CharField(source='to_user.username', read_only=True)

    class Meta:
        model = CounterOffer
        fields = ['id', 'original_proposal', 'from_username', 'to_username', 'price', 'status', 'created_at']

class TradeProposalSerializer(serializers.ModelSerializer):
    proposed_price = serializers.DecimalField(max_digits=10, decimal_places=2)
    buyer_username = serializers.CharField(source='buyer.username', read_only=True)
    listing_id = serializers.IntegerField(source='listing.id', read_only=True)
    counters = CounterOfferSerializer(many=True, read_only=True)
    listing_quantity = serializers.IntegerField(source='listing.quantity', read_only=True)
    listing_item_name = serializers.CharField(source='listing.item.name', read_only=True)
    listing_seller_username = serializers.CharField(source='listing.seller.username', read_only=True)

    class Meta:
        model = TradeProposal
        fields = "__all__"
        read_only_fields = ["buyer", "status"]

    def validate(self, data):
        listing = data.get('listing')
        proposed_price = data.get('proposed_price')
        if listing and listing.status != 'available':
            raise serializers.ValidationError('Listing is not available')
        if proposed_price is not None and proposed_price <= 0:
            raise serializers.ValidationError('Proposed price must be positive')
        return data


class PurchaseHistorySerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source="item.name", read_only=True)
    seller_username = serializers.CharField(source="seller.username", read_only=True)

    class Meta:
        model = PurchaseHistory
        fields = ["id", "item_name", "price", "seller_username", "purchased_at"]

class NotificationSerializer(serializers.ModelSerializer):
    actor_username = serializers.CharField(source='actor.username', read_only=True)
    listing_id = serializers.IntegerField(source='listing.id', read_only=True)
    proposal_id = serializers.IntegerField(source='proposal.id', read_only=True)

    class Meta:
        model = Notification
        fields = ['id', 'actor_username', 'verb', 'listing_id', 'proposal_id', 'is_read', 'created_at']

class MarketItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = MarketItem
        fields = ['id', 'name', 'price', 'stock']

class OwnedItemSerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source='item.name', read_only=True)
    item_price = serializers.DecimalField(source='item.price', max_digits=10, decimal_places=2, read_only=True)

    class Meta:
        model = OwnedItem
        fields = ['id', 'item', 'item_name', 'item_price', 'quantity']

