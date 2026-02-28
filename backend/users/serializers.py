from django.contrib.auth import get_user_model
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from .models import CustomUser, Avatar


class AvatarSerializer(serializers.ModelSerializer):
    class Meta:
        model = Avatar
        fields = ['image', 'price']


class CustomUserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True)

    owned_avatars = AvatarSerializer(many=True, read_only=True)
    avatar = AvatarSerializer(read_only=True)

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
            'avatar',            # ✅ MUST be here
            'is_developer',      # Developer flag for debug access
        ]
        read_only_fields = [
            'credits',
            'owned_avatars',
            'avatar',
            'is_developer',      # Can only be set via admin/database
        ]

    def create(self, validated_data):
        password = validated_data.pop('password')
        user = CustomUser(**validated_data)
        user.set_password(password)
        user.save()
        return user


class EmailOrUsernameTokenObtainPairSerializer(TokenObtainPairSerializer):
    """Token serializer that accepts either username or email in the `username` field.

    - Username matching is case-insensitive (maps to the real stored username).
    - Email matching is supported only when the email maps to exactly one user.
      (Email is not unique in this project, so ambiguous emails are rejected.)
    """

    def validate(self, attrs):
        identifier = (attrs.get('username') or '').strip()
        if identifier:
            User = get_user_model()

            # 1) Prefer username lookup (case-insensitive) to normalize casing.
            user_by_username = (
                User.objects.filter(username__iexact=identifier)
                .only('username')
                .first()
            )
            if user_by_username is not None:
                attrs['username'] = user_by_username.username
            else:
                # 2) If not a username, allow email when unambiguous.
                email_qs = User.objects.filter(email__iexact=identifier).only('username')
                email_count = email_qs.count()
                if email_count == 1:
                    attrs['username'] = email_qs.first().username
                elif email_count > 1:
                    raise serializers.ValidationError(
                        {
                            'username': [
                                'Multiple accounts use this email. Log in with your username instead.'
                            ]
                        }
                    )

        return super().validate(attrs)
