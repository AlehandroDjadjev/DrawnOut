from django.db import transaction
from rest_framework import generics, status, serializers
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from .models import MarketItem, MarketListing, TradeProposal, PurchaseHistory
from .serializers import MarketListingSerializer, TradeProposalSerializer, PurchaseHistorySerializer


class AvailableListingsView(generics.ListAPIView):
    queryset = MarketListing.objects.filter(status="available")
    serializer_class = MarketListingSerializer
    
class CreateListingView(generics.CreateAPIView):
    serializer_class = MarketListingSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        user = self.request.user
        item = serializer.validated_data["item"]

        if not user.inventory.filter(id=item.id).exists():
            raise serializers.ValidationError("You don't own this item.")

        user.inventory.remove(item)
        serializer.save(seller=user, status="available")

class BuyListingView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, listing_id):
        buyer = request.user

        try:
            listing = MarketListing.objects.select_related("item", "seller").get(
                id=listing_id, status="available"
            )
        except MarketListing.DoesNotExist:
            return Response({"error": "Listing not available"}, status=404)

        item = listing.item
        seller = listing.seller
        price = item.price

        if buyer.credits < price:
            return Response({"error": "Not enough credits"}, status=400)

        buyer.credits -= price
        seller.credits += price

        buyer.save()
        seller.save()

        buyer.inventory.add(item)

        listing.status = "sold"
        listing.save()

        return Response({"success": "Purchase completed"})
    
class CreateTradeProposalView(generics.CreateAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        listing = serializer.validated_data["listing"]

        if listing.status != "available":
            raise serializers.ValidationError("Listing not available")

        serializer.save(buyer=self.request.user)
        
class AcceptTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, proposal_id):
        proposal = TradeProposal.objects.select_related(
            "listing", "listing__item", "listing__seller"
        ).get(id=proposal_id, status="pending")

        seller = proposal.listing.seller
        buyer = proposal.buyer

        if request.user != seller:
            return Response({"error": "Not authorized"}, status=403)

        if buyer.credits < proposal.proposed_price:
            return Response({"error": "Buyer has insufficient credits"}, status=400)

        buyer.credits -= proposal.proposed_price
        seller.credits += proposal.proposed_price
        buyer.save()
        seller.save()

        buyer.inventory.add(proposal.listing.item)

        proposal.status = "accepted"
        proposal.save()

        proposal.listing.status = "sold"
        proposal.listing.save()

        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=proposal.listing.item,
            price=proposal.proposed_price
        )

        return Response({"success": "Trade completed"})
    
class DeclineTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        proposal = TradeProposal.objects.get(id=proposal_id, status="pending")

        if request.user != proposal.listing.seller:
            return Response({"error": "Not authorized"}, status=403)

        proposal.status = "declined"
        proposal.save()

        return Response({"status": "declined"})

class PurchaseHistoryView(generics.ListAPIView):
    serializer_class = PurchaseHistorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return PurchaseHistory.objects.filter(buyer=self.request.user)

