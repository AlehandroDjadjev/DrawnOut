from django.db import transaction
from django.db import models
from django.contrib.auth import get_user_model
from rest_framework import generics, status, serializers
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

from .models import MarketItem, MarketListing, TradeProposal, PurchaseHistory, Notification, CounterOffer, OwnedItem
from .serializers import MarketListingSerializer, TradeProposalSerializer, PurchaseHistorySerializer, NotificationSerializer, CounterOfferSerializer, MarketItemSerializer, OwnedItemSerializer


class AvailableListingsView(generics.ListAPIView):
    """List available listings but exclude listings posted by the requesting user."""
    serializer_class = MarketListingSerializer

    def get_queryset(self):
        qs = MarketListing.objects.filter(status="available").select_related('item', 'seller')
        user = getattr(self.request, 'user', None)
        if user and user.is_authenticated:
            qs = qs.exclude(seller=user)
        return qs
    
class CreateListingView(generics.CreateAPIView):
    serializer_class = MarketListingSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        user = self.request.user
        item = serializer.validated_data["item"]

        # Ensure user owns item and item has stock
        if not hasattr(user, 'inventory') or not user.inventory.filter(id=item.id).exists():
            raise serializers.ValidationError("You don't own this item.")

        if item.stock <= 0:
            raise serializers.ValidationError("Item out of stock")

        # Remove one unit from inventory and decrement stock
        user.inventory.remove(item)
        item.stock = max(0, item.stock - 1)
        item.save()

        serializer.save(seller=user, status="available")

class BuyListingView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, listing_id):
        buyer = request.user

        try:
            listing = MarketListing.objects.select_related("item", "seller").select_for_update().get(
                id=listing_id, status="available"
            )
        except MarketListing.DoesNotExist:
            return Response({"error": "Listing not available"}, status=404)

        # Prevent buying own listing
        if listing.seller == buyer:
            return Response({"error": "Cannot buy your own listing"}, status=400)

        item = listing.item
        seller = listing.seller
        price = item.price

        # Ensure buyer has credits attribute
        if not hasattr(buyer, 'credits') or buyer.credits is None:
            return Response({"error": "Buyer account has no credits field"}, status=400)

        if buyer.credits < price:
            return Response({"error": "Not enough credits"}, status=400)

        # Transfer credits
        buyer.credits -= price
        seller.credits = (seller.credits or 0) + price

        buyer.save()
        seller.save()

        # Transfer item ownership: decrement item stock and listing quantity
        if listing.quantity <= 0:
            return Response({"error": "Listing out of stock"}, status=400)
        # decrement listing
        listing.quantity -= 1
        if listing.quantity == 0:
            listing.status = 'sold'
        listing.save()
        # decrement global item stock
        if item.stock > 0:
            item.stock -= 1
            item.save()
        else:
            return Response({"error": "Item out of stock"}, status=400)

        # Add to buyer inventory if supported
        if hasattr(buyer, 'inventory'):
            # if OwnedItem exists, increment, else create
            oi, created = OwnedItem.objects.get_or_create(user=buyer, item=item)
            oi.quantity += 1
            oi.save()

        listing.save()

        # Record purchase history
        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=item,
            price=price
        )

        # Create notification for seller
        Notification.objects.create(
            recipient=seller,
            actor=buyer,
            verb=f"bought your listing {listing.id}",
            listing=listing
        )

        return Response({"success": "Purchase completed"})
    
class CreateTradeProposalView(generics.CreateAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        listing = serializer.validated_data["listing"]

        if listing.status != "available":
            raise serializers.ValidationError("Listing not available")

        # Prevent proposing on your own listing
        if listing.seller == self.request.user:
            raise serializers.ValidationError("Cannot make proposal on your own listing")

        proposal = serializer.save(buyer=self.request.user)

        # Create notification for seller
        Notification.objects.create(
            recipient=listing.seller,
            actor=self.request.user,
            verb=f"made an offer on your listing {listing.id}",
            listing=listing,
            proposal=proposal
        )
        
class ListingProposalsView(generics.ListAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        listing_id = self.kwargs.get('listing_id')
        listing = MarketListing.objects.filter(id=listing_id).first()
        if not listing:
            return TradeProposal.objects.none()
        # Only seller can view proposals for their listing
        if listing.seller != self.request.user:
            return TradeProposal.objects.none()
        return TradeProposal.objects.filter(listing_id=listing_id)

class OwnedItemsView(generics.ListAPIView):
    serializer_class = OwnedItemSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # Return OwnedItem records
        return OwnedItem.objects.filter(user=user).select_related('item')
    
class CreateListingFromItemView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, item_id):
        user = request.user
        try:
            item = MarketItem.objects.get(id=item_id)
        except MarketItem.DoesNotExist:
            return Response({'error': 'Item not found'}, status=404)
        # Check owned item record
        oi = None
        try:
            oi = OwnedItem.objects.get(user=user, item=item)
        except OwnedItem.DoesNotExist:
            return Response({'error': "You don't own this item"}, status=400)
        if oi.quantity <= 0:
            return Response({'error': 'No stock to list'}, status=400)
        # create listing with quantity 1
        listing = MarketListing.objects.create(item=item, seller=user, quantity=1)
        # decrement owned quantity and global stock
        oi.quantity -= 1
        oi.save()
        item.stock = max(0, item.stock - 1)
        item.save()
        serializer = MarketListingSerializer(listing)
        return Response(serializer.data, status=201)

class BuyListingView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, listing_id):
        buyer = request.user

        try:
            listing = MarketListing.objects.select_related("item", "seller").select_for_update().get(
                id=listing_id, status="available"
            )
        except MarketListing.DoesNotExist:
            return Response({"error": "Listing not available"}, status=404)

        # Prevent buying own listing
        if listing.seller == buyer:
            return Response({"error": "Cannot buy your own listing"}, status=400)

        item = listing.item
        seller = listing.seller
        price = item.price

        # Ensure buyer has credits attribute
        if not hasattr(buyer, 'credits') or buyer.credits is None:
            return Response({"error": "Buyer account has no credits field"}, status=400)

        if buyer.credits < price:
            return Response({"error": "Not enough credits"}, status=400)

        # Transfer credits
        buyer.credits -= price
        seller.credits = (seller.credits or 0) + price

        buyer.save()
        seller.save()

        # Transfer item ownership: decrement item stock and listing quantity
        if listing.quantity <= 0:
            return Response({"error": "Listing out of stock"}, status=400)
        # decrement listing
        listing.quantity -= 1
        if listing.quantity == 0:
            listing.status = 'sold'
        listing.save()
        # decrement global item stock
        if item.stock > 0:
            item.stock -= 1
            item.save()
        else:
            return Response({"error": "Item out of stock"}, status=400)

        # Add to buyer inventory if supported
        if hasattr(buyer, 'inventory'):
            # if OwnedItem exists, increment, else create
            oi, created = OwnedItem.objects.get_or_create(user=buyer, item=item)
            oi.quantity += 1
            oi.save()

        listing.save()

        # Record purchase history
        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=item,
            price=price
        )

        # Create notification for seller
        Notification.objects.create(
            recipient=seller,
            actor=buyer,
            verb=f"bought your listing {listing.id}",
            listing=listing
        )

        return Response({"success": "Purchase completed"})
    
class CreateTradeProposalView(generics.CreateAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        listing = serializer.validated_data["listing"]

        if listing.status != "available":
            raise serializers.ValidationError("Listing not available")

        # Prevent proposing on your own listing
        if listing.seller == self.request.user:
            raise serializers.ValidationError("Cannot make proposal on your own listing")

        proposal = serializer.save(buyer=self.request.user)

        # Create notification for seller
        Notification.objects.create(
            recipient=listing.seller,
            actor=self.request.user,
            verb=f"made an offer on your listing {listing.id}",
            listing=listing,
            proposal=proposal
        )
        
class ListingProposalsView(generics.ListAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        listing_id = self.kwargs.get('listing_id')
        listing = MarketListing.objects.filter(id=listing_id).first()
        if not listing:
            return TradeProposal.objects.none()
        # Only seller can view proposals for their listing
        if listing.seller != self.request.user:
            return TradeProposal.objects.none()
        return TradeProposal.objects.filter(listing_id=listing_id)

class MyProposalsView(generics.ListAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # proposals where user is buyer or seller
        return TradeProposal.objects.filter(models.Q(buyer=user) | models.Q(listing__seller=user)).select_related('listing', 'listing__item', 'listing__seller').distinct()

class AcceptTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, proposal_id):
        try:
            proposal = TradeProposal.objects.select_related(
                "listing", "listing__item", "listing__seller"
            ).select_for_update().get(id=proposal_id, status="pending")
        except TradeProposal.DoesNotExist:
            return Response({"error": "Proposal not found or not pending"}, status=404)

        seller = proposal.listing.seller
        buyer = proposal.buyer

        if request.user != seller:
            return Response({"error": "Not authorized"}, status=403)

        # Ensure buyer has enough credits
        if not hasattr(buyer, 'credits') or buyer.credits is None or buyer.credits < proposal.proposed_price:
            return Response({"error": "Buyer has insufficient credits"}, status=400)

        # Transfer funds
        buyer.credits -= proposal.proposed_price
        seller.credits = (seller.credits or 0) + proposal.proposed_price
        buyer.save()
        seller.save()

        # Transfer item ownership: decrement listing quantity and create OwnedItem record
        listing = proposal.listing
        item = listing.item
        if listing.quantity <= 0:
            return Response({"error": "Listing out of stock"}, status=400)
        listing.quantity -= 1
        if listing.quantity == 0:
            listing.status = 'sold'
        listing.save()

        if item.stock > 0:
            item.stock -= 1
            item.save()
        else:
            return Response({"error": "Item out of stock"}, status=400)

        oi, _ = OwnedItem.objects.get_or_create(user=buyer, item=item)
        oi.quantity += 1
        oi.save()

        proposal.status = "accepted"
        proposal.save()

        proposal.listing.status = "sold"
        proposal.listing.save()

        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=item,
            price=proposal.proposed_price
        )

        # Notify buyer
        Notification.objects.create(
            recipient=buyer,
            actor=seller,
            verb=f"accepted your offer on listing {proposal.listing.id}",
            listing=proposal.listing,
            proposal=proposal
        )

        return Response({"success": "Trade completed"})
    
class DeclineTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        try:
            proposal = TradeProposal.objects.get(id=proposal_id, status="pending")
        except TradeProposal.DoesNotExist:
            return Response({"error": "Proposal not found or not pending"}, status=404)

        if request.user != proposal.listing.seller:
            return Response({"error": "Not authorized"}, status=403)

        proposal.status = "declined"
        proposal.save()

        # Notify buyer
        Notification.objects.create(
            recipient=proposal.buyer,
            actor=request.user,
            verb=f"declined your offer on listing {proposal.listing.id}",
            listing=proposal.listing,
            proposal=proposal
        )

        return Response({"status": "declined"})

class PurchaseHistoryView(generics.ListAPIView):
    serializer_class = PurchaseHistorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return PurchaseHistory.objects.filter(buyer=self.request.user)

class NotificationsListView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)

class MarkNotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, notification_id):
        try:
            n = Notification.objects.get(id=notification_id, recipient=request.user)
        except Notification.DoesNotExist:
            return Response({"error": "Not found"}, status=404)
        n.is_read = True
        n.save()
        return Response({"success": True})

class CreateCounterOfferView(generics.CreateAPIView):
    serializer_class = CounterOfferSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        data = serializer.validated_data
        orig = data.get('original_proposal')
        if orig is None:
            raise serializers.ValidationError('Original proposal required')
        # determine participants
        from_user = self.request.user
        to_user = orig.listing.seller if orig.buyer == from_user else orig.buyer
        counter = serializer.save(from_user=from_user, to_user=to_user)
        Notification.objects.create(
            recipient=to_user,
            actor=from_user,
            verb=f'made a counter on proposal {orig.id}',
            listing=orig.listing,
            proposal=orig
        )

class RespondCounterOfferView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, counter_id, action):
        try:
            counter = CounterOffer.objects.select_related('original_proposal').get(id=counter_id, status='pending')
        except CounterOffer.DoesNotExist:
            return Response({'error':'Not found or not pending'}, status=404)
        user = request.user
        # only recipient can respond
        if counter.to_user != user:
            return Response({'error':'Not authorized'}, status=403)
        if action == 'accept':
            counter.status = 'accepted'
            counter.save()
            # mark original proposal accepted, create purchase flow
            orig = counter.original_proposal
            orig.status = 'accepted'
            orig.save()
            # process transfer similar to AcceptTradeProposalView
            buyer = orig.buyer
            seller = orig.listing.seller
            if buyer.credits < counter.price:
                return Response({'error':'Buyer has insufficient credits'}, status=400)
            buyer.credits -= counter.price
            seller.credits = (seller.credits or 0) + counter.price
            buyer.save(); seller.save()
            listing = orig.listing
            item = listing.item
            if listing.quantity <= 0:
                return Response({'error':'Listing out of stock'}, status=400)
            listing.quantity -= 1
            if listing.quantity == 0:
                listing.status = 'sold'
            listing.save()
            if item.stock > 0:
                item.stock -= 1; item.save()
            else:
                return Response({'error':'Item out of stock'}, status=400)
            oi, _ = OwnedItem.objects.get_or_create(user=buyer, item=item)
            oi.quantity += 1
            oi.save()
            PurchaseHistory.objects.create(buyer=buyer, seller=seller, item=item, price=counter.price)
            Notification.objects.create(recipient=buyer, actor=user, verb=f'accepted counter {counter.id}', listing=orig.listing, proposal=orig)
            return Response({'success':'Counter accepted'})
        elif action == 'decline':
            counter.status = 'declined'
            counter.save()
            Notification.objects.create(recipient=counter.from_user, actor=user, verb=f'declined your counter {counter.id}', listing=counter.original_proposal.listing, proposal=counter.original_proposal)
            return Response({'status':'declined'})
        else:
            return Response({'error':'invalid action'}, status=400)

class TopUpCreditsView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        if not user.is_staff:
            return Response({'error': 'staff only'}, status=403)
        amount = request.data.get('amount', 10000)
        try:
            amount = int(amount)
        except Exception:
            return Response({'error': 'invalid amount'}, status=400)
        User = get_user_model()
        updated = User.objects.update(credits=models.F('credits') + amount)
        return Response({'success': True, 'updated': updated})

