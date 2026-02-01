from rest_framework import serializers
from .models import CustomUser, Avatar


class AvatarSerializer(serializers.ModelSerializer):
    class Meta:
        model = Avatar
        fields = ['image', 'price']


class CustomUserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True)

    owned_avatars = AvatarSerializer(many=True, read_only=True)
    current_avatar = AvatarSerializer(read_only=True)

    class Meta:
        model = CustomUser
        fields = [
            'username',
            'email',
            'password',
            'first_name',
            'last_name',
            'credits',
            'owned_avatars',     # ✅ MUST be here
            'current_avatar',    # ✅ MUST be here
        ]
        read_only_fields = [
            'credits',
            'owned_avatars',
            'current_avatar',
        ]

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = CustomUser(**validated_data)
        user.set_password(password)
        user.save()
        return user
