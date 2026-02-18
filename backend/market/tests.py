from decimal import Decimal

from django.contrib.auth import get_user_model
from rest_framework.test import APIClient, APITestCase

from .models import CounterOffer, MarketItem, MarketListing, OwnedItem, TradeProposal


class MarketFlowTests(APITestCase):
    def setUp(self):
        User = get_user_model()
        self.seller = User.objects.create_user(
            username='seller',
            password='pass1234',
            credits=100,
        )
        self.buyer = User.objects.create_user(
            username='buyer',
            password='pass1234',
            credits=100,
        )
        self.third = User.objects.create_user(
            username='third',
            password='pass1234',
            credits=100,
        )

        self.item = MarketItem.objects.create(name='Avatar Hat', price=Decimal('12.00'), stock=999)
        OwnedItem.objects.create(user=self.seller, item=self.item, quantity=10)

    def _client_for(self, user):
        client = APIClient()
        client.force_authenticate(user=user)
        return client

    def test_can_list_with_custom_quantity_and_price(self):
        client = self._client_for(self.seller)
        resp = client.post(
            f'/api/market/items/{self.item.id}/list/',
            {'quantity': 3, 'price': '17.00'},
            format='json',
        )

        self.assertEqual(resp.status_code, 201)
        listing = MarketListing.objects.get(id=resp.data['id'])
        owned = OwnedItem.objects.get(user=self.seller, item=self.item)

        self.assertEqual(listing.quantity, 3)
        self.assertEqual(listing.unit_price, Decimal('17.00'))
        self.assertEqual(owned.quantity, 7)

    def test_buy_listing_respects_requested_quantity(self):
        listing = MarketListing.objects.create(
            item=self.item,
            seller=self.seller,
            quantity=5,
            unit_price=Decimal('10.00'),
            status='available',
        )

        client = self._client_for(self.buyer)
        resp = client.post(
            f'/api/market/listings/buy/{listing.id}/',
            {'quantity': 3},
            format='json',
        )

        self.assertEqual(resp.status_code, 200)

        listing.refresh_from_db()
        self.seller.refresh_from_db()
        self.buyer.refresh_from_db()
        buyer_owned = OwnedItem.objects.get(user=self.buyer, item=self.item)

        self.assertEqual(listing.quantity, 2)
        self.assertEqual(self.buyer.credits, 70)
        self.assertEqual(self.seller.credits, 130)
        self.assertEqual(buyer_owned.quantity, 3)

    def test_only_counter_recipient_can_respond(self):
        listing = MarketListing.objects.create(
            item=self.item,
            seller=self.seller,
            quantity=2,
            unit_price=Decimal('9.00'),
            status='available',
        )
        proposal = TradeProposal.objects.create(
            listing=listing,
            buyer=self.buyer,
            proposed_price=Decimal('8.00'),
        )
        counter = CounterOffer.objects.create(
            original_proposal=proposal,
            from_user=self.seller,
            to_user=self.buyer,
            price=Decimal('9.00'),
        )

        third_client = self._client_for(self.third)
        forbidden = third_client.post(
            f'/api/market/counter-offers/respond/{counter.id}/accept/',
            format='json',
        )
        self.assertEqual(forbidden.status_code, 403)

        buyer_client = self._client_for(self.buyer)
        accepted = buyer_client.post(
            f'/api/market/counter-offers/respond/{counter.id}/accept/',
            format='json',
        )
        self.assertEqual(accepted.status_code, 200)

        proposal.refresh_from_db()
        counter.refresh_from_db()
        self.assertEqual(proposal.status, 'accepted')
        self.assertEqual(counter.status, 'accepted')
