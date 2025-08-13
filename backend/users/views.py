from rest_framework.generics import CreateAPIView
from .models import CustomUser
from .serializers import CustomUserSerializer
from rest_framework.permissions import AllowAny


class RegisterView(CreateAPIView):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer
    permission_classes = [AllowAny]

    