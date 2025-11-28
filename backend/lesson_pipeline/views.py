"""API views for lesson pipeline"""
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.decorators import api_view, permission_classes as permission_classes_decorator
from django.http import HttpResponse, JsonResponse
import logging
import requests

from .pipelines.orchestrator import generate_lesson_json

logger = logging.getLogger(__name__)


class ImageProxyView(APIView):
    """
    Proxy external images to avoid CORS issues in Flutter web.
    
    GET /api/lesson-pipeline/image-proxy/?url=<image_url>
    """
    permission_classes = [AllowAny]
    
    def get(self, request):
        image_url = request.query_params.get('url')
        
        if not image_url:
            return Response({'error': 'Missing url parameter'}, status=400)
        
        try:
            logger.info(f"🖼️ Proxying image: {image_url[:100]}...")
            
            # Fetch image with proper headers
            headers = {
                'User-Agent': 'DrawnOutBot/1.0 (https://github.com/drawnout; educational@example.com)',
            }
            
            response = requests.get(image_url, headers=headers, timeout=10, stream=True)
            response.raise_for_status()
            
            # Get content type
            content_type = response.headers.get('content-type', 'image/jpeg')
            
            logger.info(f"   ✅ Fetched: {len(response.content)} bytes, type: {content_type}")
            
            # Return image with proper headers (CORS enabled)
            return HttpResponse(
                response.content,
                content_type=content_type,
                headers={
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET',
                    'Cache-Control': 'public, max-age=86400',  # Cache for 1 day
                }
            )
            
        except requests.RequestException as e:
            logger.error(f"❌ Failed to proxy image: {e}")
            return Response({'error': f'Failed to fetch image: {str(e)}'}, status=502)


@api_view(['POST'])
@permission_classes_decorator([AllowAny])
def generate_lesson_view(request):
    """
    Generate a complete lesson with images.
    
    POST /api/lesson-pipeline/generate/
    Body: {
        "prompt": "Pythagorean Theorem",
        "subject": "Mathematics",  // optional
        "duration_target": 60.0    // optional
    }
    """
    try:
        prompt = request.data.get('prompt')
        if not prompt:
            return JsonResponse({'error': 'Missing prompt'}, status=400)
        
        subject = request.data.get('subject', 'General')
        duration_target = float(request.data.get('duration_target', 60.0))
        
        logger.info(f"Generating lesson: {prompt}")
        
        result = generate_lesson_json(prompt, subject, duration_target)
        
        return JsonResponse(result, status=200)
        
    except Exception as e:
        logger.error(f"Failed to generate lesson: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return JsonResponse({'error': str(e)}, status=500)


@api_view(['GET'])
@permission_classes_decorator([AllowAny])
def health_check(request):
    """Health check endpoint"""
    return JsonResponse({'status': 'healthy', 'service': 'lesson-pipeline'})
