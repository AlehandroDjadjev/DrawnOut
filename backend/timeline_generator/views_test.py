\"\"\"API views for timeline generation\"\"\"
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import AllowAny
from django.shortcuts import get_object_or_404
from django.core.files.base import ContentFile
from lessons.models import LessonSession
from .services import TimelineGeneratorService, AudioSynthesisPipeline
from .models import Timeline, TimelineSegment
import logging

logger = logging.getLogger(__name__)


def _research_images_for_timeline(timeline_data: dict, topic: str) -> dict:
    researched = {}
    image_requests = timeline_data.get('image_requests', [])
    
    for segment in timeline_data.get('segments', []):
        for action in segment.get('drawing_actions', []):
            if action.get('type') == 'sketch_image' and not action.get('image_url'):
                metadata = action.get('metadata', {})
                img_id = metadata.get('id', f\"segment_{segment.get('sequence')}_img\")
                if img_id and not any(r.get('id') == img_id for r in image_requests):
                    image_requests.append({
                        'id': img_id,
                        'prompt': metadata.get('prompt') or action.get('text', topic),
                        'query': metadata.get('query', topic),
                        'style': metadata.get('style', 'diagram'),
                        'placement': action.get('placement'),
                    })
    
    if not image_requests:
        logger.info(\"No image_requests in timeline\")
        return researched
    
    logger.info(f\"DDG SEARCH: Researching {len(image_requests)} images...\")
    
    try:
        from duckduckgo_search import DDGS
        
        for req in image_requests:
            img_id = req.get('id', '')
            query = req.get('prompt', '') or req.get('query', '') or topic
            style = req.get('style', 'diagram')
            
            if not img_id:
                continue
            
            try:
                search_query = f\"{topic} {query} diagram illustration\"
                logger.info(f\"  DDG: {img_id} -> {search_query[:60]}...\")
                
                with DDGS() as ddgs:
                    results = list(ddgs.images(search_query, max_results=5, safesearch=\"moderate\"))
                    
                    if results:
                        best = results[0]
                        url = best.get(\"image\")
                        if url:
                            researched[img_id] = {
                                'url': url,
                                'image_url': url,
                                'source': 'duckduckgo',
                                'title': best.get('title', query),
                                'description': best.get('title', query),
                                'prompt': req.get('prompt', ''),
                                'placement': req.get('placement'),
                                'style': style,
                            }
                            logger.info(f\"    FOUND: {url[:60]}...\")
                    else:
                        logger.warning(f\"    NONE for {img_id}\")
                    
            except Exception as e:
                logger.warning(f\"  DDG error for {img_id}: {e}\")
                continue
    
    except ImportError:
        logger.error(\"DUCKDUCKGO NOT INSTALLED\")
    except Exception as e:
        logger.error(f\"DDG SEARCH FAILED: {e}\")
    
    logger.info(f\"DDG RESULT: {len(researched)}/{len(image_requests)} images\")
    return researched
