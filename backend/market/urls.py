from django.urls import path
from .views import AvailableListingsView, CreateListingView, BuyListingView, PurchaseHistoryView, AcceptTradeProposalView, CreateTradeProposalView, DeclineTradeProposalView

urlpatterns = [
    path("listings/", AvailableListingsView.as_view()),
    path("listings/create/", CreateListingView.as_view()),
    path("listings/buy/<int:listing_id>/", BuyListingView.as_view()),
    path("purchase-history/", PurchaseHistoryView.as_view()),
    path("trade-proposals/create/", CreateTradeProposalView.as_view()),
    path("trade-proposals/accept/<int:proposal_id>/", AcceptTradeProposalView.as_view()),
    path("trade-proposals/decline/<int:proposal_id>/", DeclineTradeProposalView.as_view()),
]