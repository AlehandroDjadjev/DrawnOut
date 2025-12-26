import os
import requests

BING_API_KEY = os.getenv("BING_API_KEY")
BING_API_ENDPOINT = "https://api.bing.microsoft.com/v7.0/images/search"

def search_image_by_keywords(keywords):
    """
    Use Bing Image Search API to find the most relevant image for the keywords.
    Returns a dict with 'image_url' and 'attribution' (if available).
    """
    query = " ".join(keywords)

    headers = {
        "Ocp-Apim-Subscription-Key": BING_API_KEY
    }

    params = {
        "q": query,
        "count": 1,
        "safeSearch": "Moderate",
        "imageType": "Photo"
    }

    try:
        response = requests.get(BING_API_ENDPOINT, headers=headers, params=params)
        response.raise_for_status()
        data = response.json()
        if "value" in data and len(data["value"]) > 0:
            image = data["value"][0]
            return {
                "image_url": image.get("contentUrl"),
                "attribution": image.get("hostPageDisplayUrl", ""),
                "name": image.get("name", "")
            }
        else:
            return {
                "image_url": "https://via.placeholder.com/600x400.png?text=No+Image+Found",
                "attribution": "",
                "name": "No Image Found"
            }
    except Exception as e:
        print("Bing Image Search Error:", e)
        return {
            "image_url": "https://via.placeholder.com/600x400.png?text=Error+Fetching+Image",
            "attribution": "",
            "name": "Error Fetching Image"
        }