"""Quick script to test the lesson pipeline API end-to-end."""
import requests
import json

print("=" * 60)
print("Making real API call to test full pipeline...")
print("=" * 60)

try:
    response = requests.post(
        "http://127.0.0.1:8000/api/lesson-pipeline/generate/",
        json={
            "prompt": "Photosynthesis",
            "subject": "Biology",
            "duration_target": 30.0
        },
        timeout=300
    )

    print(f"Status Code: {response.status_code}")
    print()

    result = response.json()
    
    print("Response Summary:")
    print(f"  id: {result.get('id')}")
    print(f"  topic_id: {result.get('topic_id')}")
    print(f"  indexed_image_count: {result.get('indexed_image_count')}")
    
    images = result.get("images", [])
    print(f"  images: {len(images)} total")
    for i, img in enumerate(images[:5]):
        url = img.get("base_image_url", "")
        url_display = (url[:70] + "...") if len(url) > 70 else url
        print(f"    [{i}] base_url: {url_display or '(empty)'}")
        print(f"         vector_id: {img.get('vector_id')}")
    
    # Show content
    content = result.get("content", "")
    print(f"\n  Content preview: {content[:200]}...")
    
    # Save full response
    with open("test_api_response.json", "w") as f:
        json.dump(result, f, indent=2)
    print("\n  Full response saved to test_api_response.json")
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()



