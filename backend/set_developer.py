#!/usr/bin/env python
"""
Script to set a user as a developer.

Usage:
    cd DrawnOut/backend
    python set_developer.py <username>
    
Example:
    python set_developer.py Jew
"""
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'backend.settings')
django.setup()

from users.models import CustomUser

def set_developer(username: str, is_developer: bool = True):
    """Set a user's developer status."""
    try:
        user = CustomUser.objects.get(username=username)
        user.is_developer = is_developer
        user.save()
        status = "enabled" if is_developer else "disabled"
        print(f"✅ Developer mode {status} for user: {username}")
        return True
    except CustomUser.DoesNotExist:
        print(f"❌ User not found: {username}")
        return False

def list_users():
    """List all users with their developer status."""
    users = CustomUser.objects.all()
    print(f"\nAll users ({users.count()}):")
    print("-" * 40)
    for user in users:
        dev_badge = "🔧" if user.is_developer else "  "
        print(f"  {dev_badge} {user.username}")
    print()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python set_developer.py <username>")
        print("       python set_developer.py --list")
        sys.exit(1)
    
    if sys.argv[1] == "--list":
        list_users()
    else:
        username = sys.argv[1]
        set_developer(username)
