from rest_framework.generics import CreateAPIView
from .models import CustomUser, ProfilePicture
from .serializers import CustomUserSerializer, ProfilePictureSerializer
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView


# 1. List all profile pictures
class ProfilePictureListView(generics.ListAPIView):
    queryset = ProfilePicture.objects.all()
    serializer_class = ProfilePictureSerializer
    permission_classes = [permissions.AllowAny]

# 2. Buy a profile picture
class BuyProfilePictureView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, picture_id):
        user = request.user
        try:
            picture = ProfilePicture.objects.get(id=picture_id)
        except ProfilePicture.DoesNotExist:
            return Response({'error': 'Profile picture not found'}, status=status.HTTP_404_NOT_FOUND)

        if picture in user.owned_pictures.all():
            return Response({'error': 'You already own this picture'}, status=status.HTTP_400_BAD_REQUEST)

        if user.credits < picture.price:
            return Response({'error': 'Not enough credits'}, status=status.HTTP_400_BAD_REQUEST)

        user.credits -= picture.price
        user.owned_pictures.add(picture)
        user.save()

        return Response({'message': 'Picture purchased successfully'})

# 3. Set current profile picture
class SetCurrentPFPView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, picture_id):
        user = request.user
        try:
            picture = ProfilePicture.objects.get(id=picture_id)
        except ProfilePicture.DoesNotExist:
            return Response({'error': 'Profile picture not found'}, status=status.HTTP_404_NOT_FOUND)

        if picture not in user.owned_pictures.all():
            return Response({'error': 'You do not own this picture'}, status=status.HTTP_400_BAD_REQUEST)

        user.current_pfp = picture
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
