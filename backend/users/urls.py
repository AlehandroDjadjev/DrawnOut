from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    AvatarListView,
    BuyAvatarView,
    EmailOrUsernameTokenObtainPairView,
    ProfileView,
    RegisterView,
    SetCurrentAvatarView,
    UpdateUsernameView,
)
from django.views.decorators.csrf import csrf_exempt

urlpatterns = [
    path('token/', EmailOrUsernameTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', csrf_exempt(TokenRefreshView.as_view()), name='token_refresh'),
    path('register/', RegisterView.as_view(), name='register'),
    path('profile/', ProfileView.as_view(), name='profile'),
    path('avatars/', AvatarListView.as_view(), name='avatars_list'),
    path('avatars/buy/<int:avatar_id>/', BuyAvatarView.as_view(), name='buy_avatar'),
    path('avatars/set/<int:avatar_id>/', SetCurrentAvatarView.as_view(), name='set_current_avatar'),
    path('update_username/', UpdateUsernameView.as_view(), name='update_username'),
]