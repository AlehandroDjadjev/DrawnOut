#!/usr/bin/env python
"""Test the new Wikimedia/Openverse image search"""
import requests

def test_wikimedia(query: str = "Pythagorean theorem triangle"):
    print(f"\n=== Testing Wikimedia ===")
    print(f"Query: {query}")
    
    url = "https://commons.wikimedia.org/w/api.php"
    params = {
        "action": "query",
        "generator": "search",
        "gsrnamespace": "6",
        "gsrsearch": f"{query} filetype:bitmap",
        "gsrlimit": 5,
        "prop": "imageinfo",
        "iiprop": "url|size|mime",
        "format": "json",
    }
    headers = {
        "User-Agent": "DrawnOut/1.0 (Educational whiteboard app; contact@drawnout.app)"
    }
    
    try:
        resp = requests.get(url, params=params, headers=headers, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        
        pages = data.get("query", {}).get("pages", {})
        print(f"Found {len(pages)} results")
        
        for page_id, page in list(pages.items())[:5]:
            title = page.get("title", "").replace("File:", "")
            imageinfo = page.get("imageinfo", [])
            if imageinfo:
                url = imageinfo[0].get("url", "")
                print(f"  - {title[:40]}")
                print(f"    URL: {url[:80]}...")
        
        return len(pages) > 0
        
    except Exception as e:
        print(f"ERROR: {e}")
        return False


def test_openverse(query: str = "Pythagorean theorem"):
    print(f"\n=== Testing Openverse ===")
    print(f"Query: {query}")
    
    url = "https://api.openverse.org/v1/images/"
    params = {
        "q": query,
        "page_size": 5,
    }
    
    try:
        resp = requests.get(url, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        
        results = data.get("results", [])
        print(f"Found {len(results)} results")
        
        for item in results[:5]:
            title = item.get("title", "Unknown")[:40]
            img_url = item.get("url", "")
            print(f"  - {title}")
            print(f"    URL: {img_url[:80]}...")
        
        return len(results) > 0
        
    except Exception as e:
        print(f"ERROR: {e}")
        return False


if __name__ == "__main__":
    wikimedia_ok = test_wikimedia()
    openverse_ok = test_openverse()
    
    print("\n=== Summary ===")
    print(f"Wikimedia: {'OK' if wikimedia_ok else 'FAILED'}")
    print(f"Openverse: {'OK' if openverse_ok else 'FAILED'}")
    
    if wikimedia_ok or openverse_ok:
        print("\nAt least one source works - timeline image research should succeed!")
    else:
        print("\nBoth sources failed - check network connection")

