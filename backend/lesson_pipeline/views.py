"""
API views for lesson pipeline.
"""
import logging
import requests
from django.http import JsonResponse, HttpResponseBadRequest, HttpResponse
from django.views.decorators.csrf import csrf_exempt
import json

from lesson_pipeline.pipelines.orchestrator import generate_lesson_json

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Image Proxy (CORS workaround for web frontend)
# ─────────────────────────────────────────────────────────────────────────────

@csrf_exempt
def image_proxy_view(request):
    """
    GET /api/lesson-pipeline/image-proxy/?url=<encoded_url>
    
    Proxies image requests to avoid CORS issues on web frontend.
    The frontend encodes the target URL as a query parameter.
    """
    if request.method != 'GET':
        return HttpResponseBadRequest("GET only")
    
    url = request.GET.get('url', '').strip()
    if not url:
        return HttpResponseBadRequest("'url' parameter is required")
    
    # Security: only allow http/https URLs
    if not url.startswith(('http://', 'https://')):
        return HttpResponseBadRequest("Invalid URL scheme")
    
    try:
        logger.info(f"Proxying image: {url[:100]}...")
        
        # Fetch the image with timeout
        resp = requests.get(
            url,
            timeout=30,
            headers={
                'User-Agent': 'DrawnOut-ImageProxy/1.0',
                'Accept': 'image/*',
            },
            stream=True
        )
        resp.raise_for_status()
        
        # Get content type
        content_type = resp.headers.get('Content-Type', 'image/jpeg')
        
        # Stream the response
        response = HttpResponse(
            resp.content,
            content_type=content_type
        )
        
        # Add CORS headers for web
        response['Access-Control-Allow-Origin'] = '*'
        response['Access-Control-Allow-Methods'] = 'GET, OPTIONS'
        response['Cache-Control'] = 'public, max-age=86400'  # Cache for 24h
        
        logger.info(f"Proxied image: {len(resp.content)} bytes, {content_type}")
        return response
        
    except requests.Timeout:
        logger.warning(f"Image proxy timeout: {url}")
        return HttpResponse("Image fetch timed out", status=504)
    except requests.RequestException as e:
        logger.warning(f"Image proxy error: {e}")
        return HttpResponse(f"Failed to fetch image: {e}", status=502)
    except Exception as e:
        logger.error(f"Image proxy unexpected error: {e}")
        return HttpResponse("Internal error", status=500)


@csrf_exempt
def generate_lesson_view(request):
    """
    POST /api/lesson-pipeline/generate/
    
    Request:
    {
        "prompt": "Explain DNA structure and replication",
        "subject": "Biology",  // optional
        "duration_target": 60.0  // optional, seconds
    }
    
    Response:
    {
        "ok": true,
        "lesson": {
            "id": "...",
            "prompt_id": "...",
            "content": "... script with images injected ...",
            "images": [
                {
                    "tag": {...},
                    "base_image_url": "...",
                    "final_image_url": "...",
                    "metadata": {...}
                }
            ],
            "topic_id": "...",
            "indexed_image_count": 40
        }
    }
    """
    if request.method != 'POST':
        return HttpResponseBadRequest("POST only")
    
    try:
        body = json.loads(request.body.decode('utf-8'))
    except json.JSONDecodeError:
        return HttpResponseBadRequest("Invalid JSON")
    
    prompt = body.get('prompt', '').strip()
    if not prompt:
        return HttpResponseBadRequest("'prompt' is required")
    
    subject = body.get('subject', 'General')
    duration_target = float(body.get('duration_target', 60.0))
    
    logger.info(f"Generating lesson: prompt='{prompt}', subject='{subject}'")
    
    try:
        lesson_dict = generate_lesson_json(
            prompt_text=prompt,
            subject=subject,
            duration_target=duration_target
        )
        
        return JsonResponse({
            'ok': True,
            'lesson': lesson_dict
        })
        
    except Exception as e:
        logger.error(f"Lesson generation failed: {e}", exc_info=True)
        return JsonResponse({
            'ok': False,
            'error': str(e)
        }, status=500)


@csrf_exempt
def health_check(request):
    """
    GET /api/lesson-pipeline/health/
    
    Check if all services are available.
    """
    from lesson_pipeline.services.embeddings import get_embedding_service
    from lesson_pipeline.services.vector_store import get_vector_store
    from lesson_pipeline.services.image_researcher import get_image_research_service
    from lesson_pipeline.services.script_writer import get_script_writer_service
    from lesson_pipeline.services.image_to_image import get_image_to_image_service
    
    health = {
        'ok': True,
        'services': {}
    }
    
    # Check each service
    try:
        embed_svc = get_embedding_service()
        health['services']['embeddings'] = {
            'available': embed_svc._initialized or False,
            'model': embed_svc.model_name
        }
    except Exception as e:
        health['services']['embeddings'] = {'available': False, 'error': str(e)}
        health['ok'] = False
    
    try:
        vector_svc = get_vector_store()
        stats = vector_svc.get_stats()
        health['services']['vector_store'] = {
            'available': vector_svc._initialized,
            'stats': stats
        }
    except Exception as e:
        health['services']['vector_store'] = {'available': False, 'error': str(e)}
        health['ok'] = False
    
    try:
        img_research_svc = get_image_research_service()
        health['services']['image_researcher'] = {
            'available': True
        }
    except Exception as e:
        health['services']['image_researcher'] = {'available': False, 'error': str(e)}
    
    try:
        script_svc = get_script_writer_service()
        health['services']['script_writer'] = {
            'available': script_svc.available
        }
    except Exception as e:
        health['services']['script_writer'] = {'available': False, 'error': str(e)}
        health['ok'] = False
    
    try:
        img2img_svc = get_image_to_image_service()
        health['services']['image_to_image'] = {
            'available': img2img_svc.is_available()
        }
    except Exception as e:
        health['services']['image_to_image'] = {'available': False, 'error': str(e)}
    
    status_code = 200 if health['ok'] else 503
    return JsonResponse(health, status=status_code)


