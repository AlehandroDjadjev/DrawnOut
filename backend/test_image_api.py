"""
Quick test script for the image researcher API endpoints.
Run this after starting the Django server.
"""
import requests
import json

BASE_URL = "http://localhost:8000/api/image-research"

def test_subjects():
    """Test getting supported subjects"""
    print("\n1. Testing GET /subjects/")
    response = requests.get(f"{BASE_URL}/subjects/")
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    return response.json()

def test_sources():
    """Test getting available sources"""
    print("\n2. Testing GET /sources/")
    response = requests.get(f"{BASE_URL}/sources/")
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    return response.json()

def test_search():
    """Test searching for images"""
    print("\n3. Testing POST /search/")
    data = {
        "query": "Pythagorean Theorem",
        "subject": "Maths",
        "limit": 5
    }
    print(f"Request: {json.dumps(data, indent=2)}")
    response = requests.post(
        f"{BASE_URL}/search/",
        json=data,
        headers={"Content-Type": "application/json"}
    )
    print(f"Status: {response.status_code}")
    result = response.json()
    print(f"Response: {json.dumps(result, indent=2)}")
    return result

def test_ddg_search():
    """Test DuckDuckGo search"""
    print("\n4. Testing POST /ddg-search/")
    data = {
        "query": "Maths Pythagorean Theorem diagram",
        "max_results": 10
    }
    print(f"Request: {json.dumps(data, indent=2)}")
    try:
        response = requests.post(
            f"{BASE_URL}/ddg-search/",
            json=data,
            headers={"Content-Type": "application/json"}
        )
        print(f"Status: {response.status_code}")
        result = response.json()
        print(f"Found {result.get('count', 0)} images")
        # Don't print all results, just count
        if result.get('ok'):
            print(f"✓ DDG search successful")
        else:
            print(f"✗ DDG search failed: {result.get('error')}")
        return result
    except Exception as e:
        print(f"✗ DDG search error: {e}")
        return None

if __name__ == "__main__":
    print("=" * 60)
    print("Image Researcher API Test")
    print("=" * 60)
    print("\nMake sure Django server is running:")
    print("  python manage.py runserver")
    print("=" * 60)
    
    try:
        # Test all endpoints
        test_subjects()
        test_sources()
        test_search()
        test_ddg_search()
        
        print("\n" + "=" * 60)
        print("✓ All tests completed!")
        print("=" * 60)
        
    except requests.exceptions.ConnectionError:
        print("\n✗ Connection error: Is Django server running?")
    except Exception as e:
        print(f"\n✗ Error: {e}")
        import traceback
        traceback.print_exc()


