from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django.contrib.auth import get_user_model
from django.db import models, transaction
from rest_framework import generics, serializers
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import (
    CounterOffer,
    MarketItem,
    MarketListing,
    Notification,
    OwnedItem,
    PurchaseHistory,
    TradeProposal,
)
from .serializers import (
    CounterOfferSerializer,
    MarketListingSerializer,
    NotificationSerializer,
    OwnedItemSerializer,
    PurchaseHistorySerializer,
    TradeProposalSerializer,
)


def _parse_positive_int(raw_value, field_name):
    try:
        value = int(raw_value)
    except (TypeError, ValueError):
        raise serializers.ValidationError({field_name: 'Must be a whole number'})
    if value <= 0:
        raise serializers.ValidationError({field_name: 'Must be positive'})
    return value


def _as_positive_decimal(raw_value, field_name):
    try:
        value = Decimal(str(raw_value))
    except (InvalidOperation, TypeError, ValueError):
        raise serializers.ValidationError({field_name: 'Must be a valid number'})
    if value <= 0:
        raise serializers.ValidationError({field_name: 'Must be positive'})
    return value.quantize(Decimal('0.01'))


def _price_to_credits(price: Decimal, quantity: int = 1) -> int:
    total = (price * Decimal(quantity)).quantize(Decimal('0.01'))
    return int(total.to_integral_value(rounding=ROUND_HALF_UP))


def _decline_pending_for_listing(listing, *, reason, actor=None, excluded_ids=None):
    excluded_ids = excluded_ids or []
    pending = (
        TradeProposal.objects.filter(listing=listing, status='pending')
        .exclude(id__in=excluded_ids)
        .select_related('buyer')
    )
    for proposal in pending:
        proposal.status = 'declined'
        proposal.save(update_fields=['status'])
        CounterOffer.objects.filter(
            original_proposal=proposal,
            status='pending',
        ).update(status='declined')
        Notification.objects.create(
            recipient=proposal.buyer,
            actor=actor,
            verb=reason,
            listing=listing,
            proposal=proposal,
        )


class AvailableListingsView(generics.ListAPIView):
    serializer_class = MarketListingSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = (
            MarketListing.objects.filter(status='available', quantity__gt=0)
            .select_related('item', 'seller')
            .order_by('-listed_at')
        )
        mine_only = self.request.query_params.get('mine_only')
        if mine_only in {'1', 'true', 'yes'}:
            qs = qs.filter(seller=self.request.user)
        return qs


class CreateListingView(generics.CreateAPIView):
    serializer_class = MarketListingSerializer
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def perform_create(self, serializer):
        user = self.request.user
        item = serializer.validated_data.get('item')
        qty = _parse_positive_int(serializer.validated_data.get('quantity', 1), 'quantity')
        listing_price = serializer.validated_data.get('unit_price') or item.price
        listing_price = _as_positive_decimal(listing_price, 'price')

        try:
            owned_item = OwnedItem.objects.select_for_update().get(user=user, item=item)
        except OwnedItem.DoesNotExist:
            raise serializers.ValidationError('You do not own this item')

        if owned_item.quantity < qty:
            raise serializers.ValidationError('Not enough quantity to list')

        owned_item.quantity -= qty
        owned_item.save(update_fields=['quantity'])

        serializer.save(
            seller=user,
            status='available',
            quantity=qty,
            unit_price=listing_price,
        )


class CreateListingFromItemView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, item_id):
        try:
            item = MarketItem.objects.get(id=item_id)
        except MarketItem.DoesNotExist:
            return Response({'error': 'Item not found'}, status=404)

        try:
            quantity = _parse_positive_int(request.data.get('quantity', 1), 'quantity')
            price = _as_positive_decimal(request.data.get('price', item.price), 'price')
        except serializers.ValidationError as exc:
            detail = exc.detail if isinstance(exc.detail, dict) else {'error': exc.detail}
            return Response(detail, status=400)

        try:
            owned_item = OwnedItem.objects.select_for_update().get(user=request.user, item=item)
        except OwnedItem.DoesNotExist:
            return Response({'error': 'You do not own this item'}, status=400)

        if owned_item.quantity < quantity:
            return Response({'error': 'Not enough quantity to list'}, status=400)

        owned_item.quantity -= quantity
        owned_item.save(update_fields=['quantity'])

        listing = MarketListing.objects.create(
            item=item,
            seller=request.user,
            quantity=quantity,
            unit_price=price,
            status='available',
        )
        data = MarketListingSerializer(listing, context={'request': request}).data
        return Response(data, status=201)


class CancelListingView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, listing_id):
        try:
            listing = (
                MarketListing.objects.select_related('item', 'seller')
                .select_for_update()
                .get(id=listing_id)
            )
        except MarketListing.DoesNotExist:
            return Response({'error': 'Listing not found'}, status=404)

        if listing.seller != request.user:
            return Response({'error': 'Not authorized'}, status=403)

        if listing.status != 'available' or listing.quantity <= 0:
            return Response({'error': 'Only active listings can be cancelled'}, status=400)

        returned_qty = listing.quantity
        owned_item, _ = OwnedItem.objects.select_for_update().get_or_create(
            user=request.user,
            item=listing.item,
            defaults={'quantity': 0},
        )
        owned_item.quantity += returned_qty
        owned_item.save(update_fields=['quantity'])

        listing.quantity = 0
        listing.status = 'cancelled'
        listing.save(update_fields=['quantity', 'status'])

        _decline_pending_for_listing(
            listing,
            actor=request.user,
            reason=f'cancelled listing {listing.id}',
        )

        return Response({'success': True, 'returned_quantity': returned_qty})


class BuyListingView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, listing_id):
        buyer = request.user
        try:
            listing = (
                MarketListing.objects.select_related('item', 'seller')
                .select_for_update()
                .get(id=listing_id, status='available')
            )
        except MarketListing.DoesNotExist:
            return Response({'error': 'Listing not available'}, status=404)

        if listing.seller == buyer:
            return Response({'error': 'Cannot buy your own listing'}, status=400)

        try:
            quantity = _parse_positive_int(request.data.get('quantity', 1), 'quantity')
        except serializers.ValidationError as exc:
            return Response(exc.detail, status=400)

        if listing.quantity < quantity:
            return Response({'error': 'Requested quantity exceeds listing stock'}, status=400)

        unit_price = _as_positive_decimal(listing.unit_price, 'price')
        total_credits = _price_to_credits(unit_price, quantity)

        if not hasattr(buyer, 'credits') or buyer.credits is None:
            return Response({'error': 'Buyer account has no credits'}, status=400)
        if buyer.credits < total_credits:
            return Response({'error': 'Not enough credits'}, status=400)

        seller = listing.seller
        buyer.credits -= total_credits
        seller.credits = (seller.credits or 0) + total_credits
        buyer.save(update_fields=['credits'])
        seller.save(update_fields=['credits'])

        listing.quantity -= quantity
        if listing.quantity == 0:
            listing.status = 'sold'
            listing.save(update_fields=['quantity', 'status'])
        else:
            listing.save(update_fields=['quantity'])

        owned_item, _ = OwnedItem.objects.get_or_create(
            user=buyer,
            item=listing.item,
            defaults={'quantity': 0},
        )
        owned_item.quantity += quantity
        owned_item.save(update_fields=['quantity'])

        total_price = (unit_price * Decimal(quantity)).quantize(Decimal('0.01'))
        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=listing.item,
            price=total_price,
        )

        Notification.objects.create(
            recipient=seller,
            actor=buyer,
            verb=(
                f'bought {quantity}x {listing.item.name} '
                f'for {total_credits} credits from listing {listing.id}'
            ),
            listing=listing,
        )

        if listing.status == 'sold':
            _decline_pending_for_listing(
                listing,
                actor=seller,
                reason=f'listing {listing.id} was sold out',
            )

        return Response({'success': 'Purchase completed', 'quantity': quantity})


class CreateTradeProposalView(generics.CreateAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        listing = serializer.validated_data.get('listing')
        if listing is None:
            raise serializers.ValidationError('Listing required')
        if listing.status != 'available' or listing.quantity <= 0:
            raise serializers.ValidationError('Listing not available')
        if listing.seller == self.request.user:
            raise serializers.ValidationError('Cannot make proposal on your own listing')

        already_pending = TradeProposal.objects.filter(
            listing=listing,
            buyer=self.request.user,
            status='pending',
        ).exists()
        if already_pending:
            raise serializers.ValidationError('You already have a pending offer for this listing')

        proposal = serializer.save(buyer=self.request.user)
        Notification.objects.create(
            recipient=listing.seller,
            actor=self.request.user,
            verb=f'made an offer of {proposal.proposed_price} on listing {listing.id}',
            listing=listing,
            proposal=proposal,
        )


class WithdrawTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        try:
            proposal = TradeProposal.objects.select_related('listing').get(id=proposal_id)
        except TradeProposal.DoesNotExist:
            return Response({'error': 'Not found'}, status=404)

        if proposal.buyer != request.user:
            return Response({'error': 'Not authorized'}, status=403)
        if proposal.status != 'pending':
            return Response({'error': 'Cannot withdraw non-pending proposal'}, status=400)

        proposal.status = 'declined'
        proposal.save(update_fields=['status'])
        CounterOffer.objects.filter(
            original_proposal=proposal,
            status='pending',
        ).update(status='declined')

        Notification.objects.create(
            recipient=proposal.listing.seller,
            actor=request.user,
            verb=f'withdrew an offer on listing {proposal.listing.id}',
            listing=proposal.listing,
            proposal=proposal,
        )
        return Response({'status': 'withdrawn'})


class ListingProposalsView(generics.ListAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        listing_id = self.kwargs.get('listing_id')
        listing = MarketListing.objects.filter(id=listing_id).first()
        if not listing or listing.seller != self.request.user:
            return TradeProposal.objects.none()
        return (
            TradeProposal.objects.filter(listing_id=listing_id)
            .select_related('buyer', 'listing', 'listing__item', 'listing__seller')
            .prefetch_related('counters', 'counters__from_user', 'counters__to_user')
            .order_by('-created_at')
        )


class OwnedItemsView(generics.ListAPIView):
    serializer_class = OwnedItemSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return OwnedItem.objects.filter(user=self.request.user).select_related('item')


class MyProposalsView(generics.ListAPIView):
    serializer_class = TradeProposalSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return (
            TradeProposal.objects.filter(
                models.Q(buyer=user) | models.Q(listing__seller=user),
            )
            .select_related('listing', 'listing__item', 'listing__seller', 'buyer')
            .prefetch_related('counters', 'counters__from_user', 'counters__to_user')
            .distinct()
            .order_by('-created_at')
        )


class AcceptTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, proposal_id):
        try:
            proposal = (
                TradeProposal.objects.select_related(
                    'listing',
                    'listing__item',
                    'listing__seller',
                    'buyer',
                )
                .select_for_update()
                .get(id=proposal_id, status='pending')
            )
        except TradeProposal.DoesNotExist:
            return Response({'error': 'Proposal not found or not pending'}, status=404)

        listing = proposal.listing
        seller = listing.seller
        buyer = proposal.buyer

        if request.user != seller:
            return Response({'error': 'Not authorized'}, status=403)
        if listing.status != 'available' or listing.quantity <= 0:
            return Response({'error': 'Listing not available'}, status=400)

        credits = _price_to_credits(_as_positive_decimal(proposal.proposed_price, 'proposed_price'))
        if buyer.credits is None or buyer.credits < credits:
            return Response({'error': 'Buyer has insufficient credits'}, status=400)

        buyer.credits -= credits
        seller.credits = (seller.credits or 0) + credits
        buyer.save(update_fields=['credits'])
        seller.save(update_fields=['credits'])

        listing.quantity -= 1
        if listing.quantity == 0:
            listing.status = 'sold'
            listing.save(update_fields=['quantity', 'status'])
        else:
            listing.save(update_fields=['quantity'])

        owned_item, _ = OwnedItem.objects.get_or_create(
            user=buyer,
            item=listing.item,
            defaults={'quantity': 0},
        )
        owned_item.quantity += 1
        owned_item.save(update_fields=['quantity'])

        proposal.status = 'accepted'
        proposal.save(update_fields=['status'])
        CounterOffer.objects.filter(
            original_proposal=proposal,
            status='pending',
        ).update(status='declined')

        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=listing.item,
            price=proposal.proposed_price,
        )

        Notification.objects.create(
            recipient=buyer,
            actor=seller,
            verb=f'accepted your offer on listing {listing.id}',
            listing=listing,
            proposal=proposal,
        )

        if listing.status == 'sold':
            _decline_pending_for_listing(
                listing,
                actor=seller,
                reason=f'listing {listing.id} was sold out',
                excluded_ids=[proposal.id],
            )

        return Response({'success': 'Trade completed'})


class DeclineTradeProposalView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, proposal_id):
        try:
            proposal = TradeProposal.objects.select_related('listing', 'buyer').get(
                id=proposal_id,
                status='pending',
            )
        except TradeProposal.DoesNotExist:
            return Response({'error': 'Proposal not found or not pending'}, status=404)

        if request.user != proposal.listing.seller:
            return Response({'error': 'Not authorized'}, status=403)

        proposal.status = 'declined'
        proposal.save(update_fields=['status'])
        CounterOffer.objects.filter(
            original_proposal=proposal,
            status='pending',
        ).update(status='declined')

        Notification.objects.create(
            recipient=proposal.buyer,
            actor=request.user,
            verb=f'declined your offer on listing {proposal.listing.id}',
            listing=proposal.listing,
            proposal=proposal,
        )
        return Response({'status': 'declined'})


class PurchaseHistoryView(generics.ListAPIView):
    serializer_class = PurchaseHistorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return PurchaseHistory.objects.filter(buyer=self.request.user).select_related(
            'item',
            'seller',
        )


class NotificationsListView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user).select_related(
            'actor',
            'listing',
            'listing__item',
            'proposal',
        )


class MarkNotificationReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, notification_id):
        try:
            notification = Notification.objects.get(id=notification_id, recipient=request.user)
        except Notification.DoesNotExist:
            return Response({'error': 'Not found'}, status=404)

        notification.is_read = True
        notification.save(update_fields=['is_read'])
        return Response({'success': True})


class MarkAllNotificationsReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        updated = Notification.objects.filter(
            recipient=request.user,
            is_read=False,
        ).update(is_read=True)
        return Response({'success': True, 'updated': updated})


class CreateCounterOfferView(generics.CreateAPIView):
    serializer_class = CounterOfferSerializer
    permission_classes = [IsAuthenticated]

    def perform_create(self, serializer):
        original_proposal = serializer.validated_data.get('original_proposal')
        if original_proposal is None:
            raise serializers.ValidationError('Original proposal required')
        if original_proposal.status != 'pending':
            raise serializers.ValidationError('Original proposal is no longer pending')

        listing = original_proposal.listing
        from_user = self.request.user
        if from_user not in (original_proposal.buyer, listing.seller):
            raise serializers.ValidationError('Not authorized for this proposal')

        if CounterOffer.objects.filter(
            original_proposal=original_proposal,
            status='pending',
        ).exists():
            raise serializers.ValidationError('A pending counter already exists')

        to_user = listing.seller if from_user == original_proposal.buyer else original_proposal.buyer
        counter = serializer.save(from_user=from_user, to_user=to_user)
        Notification.objects.create(
            recipient=to_user,
            actor=from_user,
            verb=f'made a counter offer of {counter.price} on proposal {original_proposal.id}',
            listing=listing,
            proposal=original_proposal,
        )


class RespondCounterOfferView(APIView):
    permission_classes = [IsAuthenticated]

    @transaction.atomic
    def post(self, request, counter_id, action):
        try:
            counter = (
                CounterOffer.objects.select_related(
                    'original_proposal',
                    'original_proposal__listing',
                    'original_proposal__listing__item',
                    'original_proposal__listing__seller',
                    'original_proposal__buyer',
                    'from_user',
                    'to_user',
                )
                .select_for_update()
                .get(id=counter_id, status='pending')
            )
        except CounterOffer.DoesNotExist:
            return Response({'error': 'Not found or not pending'}, status=404)

        user = request.user
        if counter.to_user != user:
            return Response({'error': 'Not authorized'}, status=403)

        action = action.lower()
        if action not in {'accept', 'decline'}:
            return Response({'error': 'invalid action'}, status=400)

        original_proposal = counter.original_proposal
        listing = original_proposal.listing

        if action == 'decline':
            counter.status = 'declined'
            counter.save(update_fields=['status'])
            Notification.objects.create(
                recipient=counter.from_user,
                actor=user,
                verb=f'declined your counter offer on proposal {original_proposal.id}',
                listing=listing,
                proposal=original_proposal,
            )
            return Response({'status': 'declined'})

        if original_proposal.status != 'pending':
            return Response({'error': 'Original proposal is no longer pending'}, status=400)
        if listing.status != 'available' or listing.quantity <= 0:
            return Response({'error': 'Listing not available'}, status=400)

        buyer = original_proposal.buyer
        seller = listing.seller
        credits = _price_to_credits(_as_positive_decimal(counter.price, 'price'))
        if buyer.credits is None or buyer.credits < credits:
            return Response({'error': 'Buyer has insufficient credits'}, status=400)

        buyer.credits -= credits
        seller.credits = (seller.credits or 0) + credits
        buyer.save(update_fields=['credits'])
        seller.save(update_fields=['credits'])

        listing.quantity -= 1
        if listing.quantity == 0:
            listing.status = 'sold'
            listing.save(update_fields=['quantity', 'status'])
        else:
            listing.save(update_fields=['quantity'])

        owned_item, _ = OwnedItem.objects.get_or_create(
            user=buyer,
            item=listing.item,
            defaults={'quantity': 0},
        )
        owned_item.quantity += 1
        owned_item.save(update_fields=['quantity'])

        counter.status = 'accepted'
        counter.save(update_fields=['status'])

        original_proposal.status = 'accepted'
        original_proposal.save(update_fields=['status'])

        CounterOffer.objects.filter(
            original_proposal=original_proposal,
            status='pending',
        ).exclude(id=counter.id).update(status='declined')

        PurchaseHistory.objects.create(
            buyer=buyer,
            seller=seller,
            item=listing.item,
            price=counter.price,
        )

        Notification.objects.create(
            recipient=buyer,
            actor=user,
            verb=f'accepted your counter offer on listing {listing.id}',
            listing=listing,
            proposal=original_proposal,
        )

        if listing.status == 'sold':
            _decline_pending_for_listing(
                listing,
                actor=seller,
                reason=f'listing {listing.id} was sold out',
                excluded_ids=[original_proposal.id],
            )

        return Response({'success': 'Counter accepted'})


class TopUpCreditsView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if not request.user.is_staff:
            return Response({'error': 'staff only'}, status=403)

        amount = request.data.get('amount', 10000)
        try:
            amount = int(amount)
        except (TypeError, ValueError):
            return Response({'error': 'invalid amount'}, status=400)

        User = get_user_model()
        updated = User.objects.update(credits=models.F('credits') + amount)
        return Response({'success': True, 'updated': updated})
