"""
Openverse OAuth2 authentication helper.
Handles token retrieval and caching.
"""
import os
import json
import time
import requests
from pathlib import Path

# Token cache file
TOKEN_CACHE_FILE = Path(__file__).parent / '.openverse_token_cache.json'

def get_openverse_token():
    """
    Get a valid Openverse API access token.
    
    Uses cached token if available and not expired, otherwise fetches a new one.
    
    Returns:
        str: Bearer token or None if auth fails
    """
    client_id = os.getenv('OPENVERSE_CLIENT_ID')
    client_secret = os.getenv('OPENVERSE_CLIENT_SECRET')
    
    if not client_id or not client_secret:
        return None
    
    # Check cache
    if TOKEN_CACHE_FILE.exists():
        try:
            with open(TOKEN_CACHE_FILE, 'r') as f:
                cache = json.load(f)
            
            # Check if token is still valid (with 5 minute buffer)
            expires_at = cache.get('expires_at', 0)
            if time.time() < (expires_at - 300):  # 5 min buffer
                return cache.get('access_token')
        except Exception:
            pass
    
    # Fetch new token
    try:
        response = requests.post(
            'https://api.openverse.org/v1/auth_tokens/token/',
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            data={
                'grant_type': 'client_credentials',
                'client_id': client_id,
                'client_secret': client_secret
            },
            timeout=10
        )
        
        if response.status_code == 200:
            token_data = response.json()
            access_token = token_data.get('access_token')
            expires_in = token_data.get('expires_in', 36000)
            
            # Cache the token
            cache = {
                'access_token': access_token,
                'expires_at': time.time() + expires_in,
                'fetched_at': time.time()
            }
            
            try:
                with open(TOKEN_CACHE_FILE, 'w') as f:
                    json.dump(cache, f)
            except Exception:
                pass  # Cache write failed, but we have the token
            
            return access_token
        else:
            print(f"[OPENVERSE_AUTH] Failed to get token: {response.status_code}")
            return None
            
    except Exception as e:
        print(f"[OPENVERSE_AUTH] Error getting token: {e}")
        return None


def get_auth_headers():
    """
    Get headers with Openverse authentication.
    
    Returns:
        dict: Headers with Authorization bearer token if available
    """
    token = get_openverse_token()
    headers = {"User-Agent": "diag-scrape/0.2 (+openverse-oauth2)"}
    
    if token:
        headers["Authorization"] = f"Bearer {token}"
    
    return headers









