from django.urls import path
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from .views import RegisterView, ProfileView, SetCurrentPFPView, BuyProfilePictureView, ProfilePictureListView
from django.views.decorators.csrf import csrf_exempt

urlpatterns = [
    path('token/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', csrf_exempt(TokenRefreshView.as_view()), name='token_refresh'),
    path('register/', RegisterView.as_view(), name='register'),
    path('profile/', ProfileView.as_view(), name='profile'),
    path('profile-pictures/', ProfilePictureListView.as_view(), name='profile_pictures_list'),
    path('profile-pictures/buy/<int:picture_id>/', BuyProfilePictureView.as_view(), name='buy_profile_picture'),
    path('profile-pictures/set/<int:picture_id>/', SetCurrentPFPView.as_view(), name='set_current_pfp'),
]