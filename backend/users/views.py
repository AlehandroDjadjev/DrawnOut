from rest_framework.generics import CreateAPIView
from .models import CustomUser, Avatar
from .serializers import CustomUserSerializer, AvatarSerializer
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView


# 1. List all profile pictures
class AvatarListView(generics.ListAPIView):
    queryset = Avatar.objects.all()
    serializer_class = AvatarSerializer
    permission_classes = [permissions.AllowAny]

# 2. Buy a profile picture
class BuyAvatarView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, picture_id):
        user = request.user
        try:
            picture = Avatar.objects.get(id=picture_id)
        except Avatar.DoesNotExist:
            return Response({'error': 'Avatar not found'}, status=status.HTTP_404_NOT_FOUND)

        if picture in user.owned_avatars.all():
            return Response({'error': 'You already own this avatar'}, status=status.HTTP_400_BAD_REQUEST)

        if user.credits < picture.price:
            return Response({'error': 'Not enough credits'}, status=status.HTTP_400_BAD_REQUEST)

        user.credits -= picture.price
        user.owned_pictures.add(picture)
        user.save()

        return Response({'message': 'Picture purchased successfully'})

# 3. Set current profile picture
class SetCurrentAvatarView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, avatar_id):
        user = request.user
        try:
            picture = Avatar.objects.get(id=avatar_id)
        except Avatar.DoesNotExist:
            return Response({'error': 'Avatar not found'}, status=status.HTTP_404_NOT_FOUND)

        if picture not in user.owned_avatars.all():
            return Response({'error': 'You do not own this avatar'}, status=status.HTTP_400_BAD_REQUEST)

        user.avatar = picture
        user.save()

        return Response({'message': 'Profile picture updated successfully'})


class RegisterView(CreateAPIView):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserSerializer
    permission_classes = [permissions.AllowAny]

    
class ProfileView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        serializer = CustomUserSerializer(request.user)
        return Response(serializer.data)

class UpdateUsernameView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def put(self, request):
        user = request.user
        new_username = request.data.get("username")

        if not new_username:
            return Response(
                {"error": "Username is required"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Ensure the username is not taken
        if CustomUser.objects.filter(username=new_username).exclude(id=user.id).exists():
            return Response(
                {"error": "This username is already taken"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user.username = new_username
        user.save()
        return Response(
            {"message": "Username updated successfully", "username": new_username},
            status=status.HTTP_200_OK,
        )
