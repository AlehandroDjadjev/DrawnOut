from rest_framework import serializers
from .models import CustomUser, ProfilePicture

class ProfilePictureSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProfilePicture
        fields = ['image', 'price']


class CustomUserSerializer(serializers.ModelSerializer):
    # Keep password write-only so it is only used on creation
    password = serializers.CharField(write_only=True, required=True)
    owned_pictures = ProfilePictureSerializer(many=True, read_only=True)
    current_pfp = ProfilePictureSerializer(read_only=True)

    class Meta:
        model = CustomUser
        fields = ['username', 'email', 'password', 'first_name', 'last_name', 'credits', 'owned_pictures', 'current_pfp']

    def create(self, validated_data):
        # Remove password from validated_data to handle hashing
        password = validated_data.pop('password')
        user = CustomUser(**validated_data)
        user.set_password(password)  # hash the password
        user.save()
        return user
    