"""
API endpoints for image research functionality.
Wraps Imageresearcher.py functions as REST endpoints.
"""
import os
import json
import sys
from pathlib import Path
from django.http import JsonResponse, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt
from django.conf import settings

# Add the image_researcher directory to Python path
IMAGE_RESEARCHER_DIR = Path(__file__).parent
sys.path.insert(0, str(IMAGE_RESEARCHER_DIR))

# Import the Imageresearcher module
try:
    import Imageresearcher as ir
except ImportError as e:
    print(f"Failed to import Imageresearcher: {e}")
    ir = None


@csrf_exempt
def search_images(request):
    """
    POST /api/image-research/search/
    {
        "query": "Prokaryotic Cells",
        "subject": "Biology",
        "limit": 10,
        "sources": ["openstax", "wikimedia"]  // optional, defaults to all
    }
    
    Returns:
    {
        "ok": true,
        "results": [
            {
                "source": "openstax",
                "images": ["path1", "path2", ...],
                "count": 5
            }
        ],
        "total_images": 10
    }
    """
    if request.method != "POST":
        return HttpResponseBadRequest("POST JSON only")
    
    if not ir:
        return JsonResponse({
            "ok": False,
            "error": "Imageresearcher module not available"
        }, status=500)
    
    try:
        body = json.loads((request.body or b"{}").decode("utf-8"))
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")
    
    query = body.get("query", "").strip()
    subject = body.get("subject", "").strip()
    limit = body.get("limit", 10)
    requested_sources = body.get("sources", [])
    
    if not query:
        return HttpResponseBadRequest("'query' is required")
    
    if not subject:
        return HttpResponseBadRequest("'subject' is required")
    
    # Settings for the image researcher
    settings_dict = {
        "query_field": query,
        "limit_field": limit,
        "pagination_field": 1,
        "format_field": "json",
    }
    
    # Read sources
    sources = ir.read_sources()
    
    results = []
    total_images = 0
    
    for src in sources:
        # Filter sources if specified
        if requested_sources and src.name not in requested_sources:
            continue
        
        try:
            if src.type == "API":
                # API-based source
                status, data, _ = ir.send_request(src, settings_dict)
                if status == 200 and data is not None:
                    parse_fn = ir.PARSERS.get(src.name)
                    if parse_fn:
                        parse_fn(src, data)
            else:
                # Non-API source (scraping)
                ir.handle_result_no_api(src, query, subject, hard_image_cap=limit)
            
            # Collect results
            images = getattr(src, 'img_paths', [])
            results.append({
                "source": src.name,
                "images": images,
                "count": len(images)
            })
            total_images += len(images)
            
        except Exception as e:
            results.append({
                "source": src.name,
                "images": [],
                "count": 0,
                "error": str(e)
            })
    
    return JsonResponse({
        "ok": True,
        "results": results,
        "total_images": total_images,
        "query": query,
        "subject": subject
    })


@csrf_exempt
def list_sources(request):
    """
    GET /api/image-research/sources/
    
    Returns list of available image sources:
    {
        "ok": true,
        "sources": [
            {"name": "openstax", "type": "API", "url": "..."},
            {"name": "wikimedia", "type": "NOAPI", "url": "..."}
        ]
    }
    """
    if not ir:
        return JsonResponse({
            "ok": False,
            "error": "Imageresearcher module not available"
        }, status=500)
    
    try:
        sources = ir.read_sources()
        source_list = [
            {
                "name": src.name,
                "type": src.type,
                "url": src.url
            }
            for src in sources
        ]
        
        return JsonResponse({
            "ok": True,
            "sources": source_list
        })
    except Exception as e:
        return JsonResponse({
            "ok": False,
            "error": str(e)
        }, status=500)


@csrf_exempt
def get_subjects(request):
    """
    GET /api/image-research/subjects/
    
    Returns list of supported subjects:
    {
        "ok": true,
        "subjects": ["Maths", "Physics", "Biology", "Chemistry", "Geography"]
    }
    """
    if not ir:
        return JsonResponse({
            "ok": False,
            "error": "Imageresearcher module not available"
        }, status=500)
    
    return JsonResponse({
        "ok": True,
        "subjects": ir.SUBJECTS
    })


@csrf_exempt
def search_duckduckgo(request):
    """
    POST /api/image-research/ddg-search/
    {
        "query": "Biology Prokaryotic Cells diagram",
        "max_results": 100
    }
    
    Search DuckDuckGo for images (may rate-limit).
    
    Returns:
    {
        "ok": true,
        "results": [...]
    }
    """
    if request.method != "POST":
        return HttpResponseBadRequest("POST JSON only")
    
    if not ir:
        return JsonResponse({
            "ok": False,
            "error": "Imageresearcher module not available"
        }, status=500)
    
    try:
        body = json.loads((request.body or b"{}").decode("utf-8"))
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")
    
    query = body.get("query", "").strip()
    max_results = body.get("max_results", 100)
    
    if not query:
        return HttpResponseBadRequest("'query' is required")
    
    try:
        from duckduckgo_search import DDGS
        
        with DDGS() as ddgs:
            results = list(ddgs.images(query, max_results=max_results, safesearch="moderate"))
        
        return JsonResponse({
            "ok": True,
            "results": results,
            "count": len(results)
        })
    except Exception as e:
        return JsonResponse({
            "ok": False,
            "error": str(e)
        }, status=500)



