from rest_framework import serializers

from .models import (
    CounterOffer,
    MarketItem,
    MarketListing,
    Notification,
    OwnedItem,
    PurchaseHistory,
    TradeProposal,
)


class MarketListingSerializer(serializers.ModelSerializer):
    item_id = serializers.PrimaryKeyRelatedField(
        queryset=MarketItem.objects.all(),
        write_only=True,
        source="item",
    )
    item_name = serializers.CharField(source="item.name", read_only=True)
    item_stock = serializers.IntegerField(source="item.stock", read_only=True)
    price = serializers.DecimalField(
        source="unit_price",
        max_digits=10,
        decimal_places=2,
        required=False,
    )
    default_item_price = serializers.DecimalField(
        source="item.price",
        max_digits=10,
        decimal_places=2,
        read_only=True,
    )
    seller_username = serializers.CharField(source="seller.username", read_only=True)
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = MarketListing
        fields = [
            "id",
            "item_id",
            "item_name",
            "item_stock",
            "price",
            "default_item_price",
            "listed_at",
            "status",
            "seller_username",
            "quantity",
            "is_mine",
        ]
        read_only_fields = ["status", "seller_username", "is_mine"]

    def get_is_mine(self, obj):
        request = self.context.get("request")
        return bool(request and request.user.is_authenticated and obj.seller_id == request.user.id)

    def validate_quantity(self, value):
        if value <= 0:
            raise serializers.ValidationError("Quantity must be positive")
        return value

    def validate_price(self, value):
        if value <= 0:
            raise serializers.ValidationError("Price must be positive")
        return value


class CounterOfferSerializer(serializers.ModelSerializer):
    from_username = serializers.CharField(source="from_user.username", read_only=True)
    to_username = serializers.CharField(source="to_user.username", read_only=True)

    class Meta:
        model = CounterOffer
        fields = [
            "id",
            "original_proposal",
            "from_username",
            "to_username",
            "price",
            "status",
            "created_at",
        ]
        read_only_fields = ["status", "from_username", "to_username", "created_at"]

    def validate_price(self, value):
        if value <= 0:
            raise serializers.ValidationError("Counter price must be positive")
        return value


class TradeProposalSerializer(serializers.ModelSerializer):
    listing = serializers.PrimaryKeyRelatedField(queryset=MarketListing.objects.all())
    proposed_price = serializers.DecimalField(max_digits=10, decimal_places=2)
    buyer = serializers.CharField(source="buyer.username", read_only=True)
    buyer_username = serializers.CharField(source="buyer.username", read_only=True)
    listing_id = serializers.IntegerField(source="listing.id", read_only=True)
    counters = CounterOfferSerializer(many=True, read_only=True)
    listing_quantity = serializers.IntegerField(source="listing.quantity", read_only=True)
    listing_item_name = serializers.CharField(source="listing.item.name", read_only=True)
    listing_seller_username = serializers.CharField(
        source="listing.seller.username",
        read_only=True,
    )

    class Meta:
        model = TradeProposal
        fields = "__all__"
        read_only_fields = ["buyer", "status", "created_at"]

    def validate(self, data):
        listing = data.get("listing")
        proposed_price = data.get("proposed_price")
        if listing is None:
            raise serializers.ValidationError("Listing is required")
        if listing.status != "available" or listing.quantity <= 0:
            raise serializers.ValidationError("Listing is not available")
        if proposed_price is None or proposed_price <= 0:
            raise serializers.ValidationError("Proposed price must be positive")
        return data


class PurchaseHistorySerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source="item.name", read_only=True)
    seller_username = serializers.CharField(source="seller.username", read_only=True)

    class Meta:
        model = PurchaseHistory
        fields = ["id", "item_name", "price", "seller_username", "purchased_at"]


class NotificationSerializer(serializers.ModelSerializer):
    actor_username = serializers.CharField(source="actor.username", read_only=True)
    listing_id = serializers.IntegerField(source="listing.id", read_only=True)
    proposal_id = serializers.IntegerField(source="proposal.id", read_only=True)
    item_name = serializers.CharField(source="listing.item.name", read_only=True)

    class Meta:
        model = Notification
        fields = [
            "id",
            "actor_username",
            "verb",
            "listing_id",
            "proposal_id",
            "item_name",
            "is_read",
            "created_at",
        ]


class MarketItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = MarketItem
        fields = ["id", "name", "price", "stock"]


class OwnedItemSerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source="item.name", read_only=True)
    item_price = serializers.DecimalField(
        source="item.price",
        max_digits=10,
        decimal_places=2,
        read_only=True,
    )

    class Meta:
        model = OwnedItem
        fields = ["id", "item", "item_name", "item_price", "quantity"]

