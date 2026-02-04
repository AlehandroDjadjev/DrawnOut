from rest_framework import serializers
from .models import MarketItem, MarketListing, TradeProposal, PurchaseHistory

class MarketListingSerializer(serializers.ModelSerializer):
    item_id = serializers.PrimaryKeyRelatedField(
        queryset=MarketItem.objects.all(),
        write_only=True,
        source="item"
    )
    item_name = serializers.CharField(source="item.name", read_only=True)
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
            "price",
            "listed_at",
            "status",
            "seller_username",
        ]

class TradeProposalSerializer(serializers.ModelSerializer):
    class Meta:
        model = TradeProposal
        fields = "__all__"
        read_only_fields = ["buyer", "status"]


class PurchaseHistorySerializer(serializers.ModelSerializer):
    item_name = serializers.CharField(source="item.name", read_only=True)
    seller_username = serializers.CharField(source="seller.username", read_only=True)

    class Meta:
        model = PurchaseHistory
        fields = ["id", "item_name", "price", "seller_username", "purchased_at"]

