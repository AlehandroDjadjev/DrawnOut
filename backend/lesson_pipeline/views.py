"""
API views for lesson pipeline.
"""
import logging
from django.http import JsonResponse, HttpResponseBadRequest
from django.views.decorators.csrf import csrf_exempt
import json

from lesson_pipeline.pipelines.orchestrator import generate_lesson_json

logger = logging.getLogger(__name__)


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


