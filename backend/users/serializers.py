from rest_framework import serializers
from .models import CustomUser

class CustomUserSerializer(serializers.ModelSerializer):
    # Keep password write-only so it is only used on creation
    password = serializers.CharField(write_only=True, required=True)

    class Meta:
        model = CustomUser
        fields = ['username', 'email', 'password', 'first_name', 'last_name', 'pfp']

    def create(self, validated_data):
        # Remove password from validated_data to handle hashing
        password = validated_data.pop('password')
        user = CustomUser(**validated_data)
        user.set_password(password)  # hash the password
        user.save()
        return user
