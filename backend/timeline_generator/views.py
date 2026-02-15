"""API views for timeline generation - v3"""
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

# Import the lesson pipeline's orchestrator - same as save_lesson_output.py uses
from lesson_pipeline.pipelines.orchestrator import generate_lesson_json

logger = logging.getLogger(__name__)


def _get_images_from_lesson_pipeline(topic: str, subject: str = "General") -> dict:
    """
    Get images using the lesson pipeline - EXACT same approach as save_lesson_output.py
    
    Calls generate_lesson_json() which:
    1. Does image research in background (Imageresearcher)
    2. Resolves images to base_image_url via Pinecone
    3. Returns images with URLs ready to use
    
    Returns:
        Dict mapping image IDs to image data with 'url', 'image_url', etc.
    """
    logger.info(f"[LessonPipeline] Generating lesson for images: {topic}")
    
    # Call the SAME function that /api/lesson-pipeline/generate/ uses
    lesson_data = generate_lesson_json(
        prompt_text=topic,
        subject=subject,
        duration_target=60.0,  # Duration doesn't matter for images
    )
    
    # Extract images - same structure as save_lesson_output.py reads
    images = lesson_data.get('images', [])
    
    if not images:
        raise RuntimeError(f"Lesson pipeline returned 0 images for topic: '{topic}'")
    
    logger.info(f"[LessonPipeline] Got {len(images)} images from lesson pipeline")
    
    # Build lookup dict by tag ID
    image_lookup = {}
    for img in images:
        tag = img.get('tag', {})
        tag_id = tag.get('id', '')
        base_url = img.get('base_image_url', '')
        final_url = img.get('final_image_url', '') or base_url
        
        if tag_id and base_url:
            image_lookup[tag_id] = {
                'url': base_url,
                'image_url': base_url,
                'final_url': final_url,
                'source': 'lesson_pipeline',
                'title': tag.get('query', topic),
                'description': tag.get('prompt', ''),
                'prompt': tag.get('prompt', ''),
                'style': tag.get('style', 'diagram'),
            }
            logger.info(f"  [{tag_id}] {base_url[:60]}...")
    
    return image_lookup


def _research_images_for_timeline(timeline_data: dict, topic: str) -> dict:
    """
    Get images for timeline using the lesson pipeline.
    
    Uses the EXACT SAME approach as save_lesson_output.py:
    - Calls generate_lesson_json() to get images with base_image_url
    - Maps those images to the timeline's image requests
    
    Raises RuntimeError if lesson pipeline fails.
    """
    researched = {}
    image_requests = timeline_data.get('image_requests', [])
    
    # Scan segments for sketch_image actions that need URLs
    for segment in timeline_data.get('segments', []):
        for action in segment.get('drawing_actions', []):
            if action.get('type') == 'sketch_image' and not action.get('image_url'):
                metadata = action.get('metadata', {})
                img_id = metadata.get('id', f"segment_{segment.get('sequence')}_img")
                if img_id and not any(r.get('id') == img_id for r in image_requests):
                    image_requests.append({
                        'id': img_id,
                        'prompt': metadata.get('prompt') or action.get('text', topic),
                        'query': metadata.get('query', topic),
                        'style': metadata.get('style', 'diagram'),
                        'placement': action.get('placement'),
                    })
    
    if not image_requests:
        logger.info("No images to research")
        return researched
    
    logger.info(f"Getting {len(image_requests)} images via lesson_pipeline...")
    
    # Get images from lesson pipeline - same as save_lesson_output.py
    image_lookup = _get_images_from_lesson_pipeline(topic, "General")
    
    # Map lesson pipeline images to timeline image requests
    # The lesson pipeline generates its own image IDs, so we match by position
    pipeline_images = list(image_lookup.values())
    
    for i, req in enumerate(image_requests):
        img_id = req.get('id', '')
        if not img_id:
            continue
        
        # Use pipeline image if available (by position), otherwise first available
        if i < len(pipeline_images):
            img_data = pipeline_images[i]
        elif pipeline_images:
            img_data = pipeline_images[0]  # Fallback to first image
        else:
            raise RuntimeError(f"No images available for {img_id}")
        
        researched[img_id] = {
            'url': img_data['url'],
            'image_url': img_data['url'],
            'source': img_data.get('source', 'lesson_pipeline'),
            'title': img_data.get('title', topic),
            'description': img_data.get('description', ''),
            'prompt': req.get('prompt', ''),
            'placement': req.get('placement'),
            'style': req.get('style', 'diagram'),
        }
        logger.info(f"  [{img_id}] -> {img_data['url'][:60]}...")
    
    logger.info(f"Got {len(researched)}/{len(image_requests)} images from lesson_pipeline")
    return researched


class GenerateTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request, session_id: int):
        try:
            session = LessonSession.objects.get(pk=session_id)
        except LessonSession.DoesNotExist:
            return Response({"error": "Session not found"}, status=404)
        
        regenerate = request.data.get('regenerate', False)
        if not regenerate:
            existing = Timeline.objects.filter(session=session).order_by('-created_at').first()
            if existing:
                logger.info(f"Using cached timeline {existing.id}")
                return Response({
                    "timeline_id": existing.id,
                    "session_id": session.id,
                    "segments": existing.segments,
                    "total_duration": existing.total_duration,
                    "status": "cached"
                })
        
        duration_target = float(request.data.get('duration_target', 60.0))
        logger.info(f"Generating timeline for session {session_id}")
        
        try:
            generator = TimelineGeneratorService()
            timeline_data = generator.generate_timeline(
                lesson_plan={'lesson_plan': session.lesson_plan},
                topic=session.topic,
                duration_target=duration_target
            )
            
            if not timeline_data:
                return Response({"error": "Failed to generate timeline"}, status=500)
            
            logger.info(f"Timeline: {len(timeline_data.get('segments', []))} segments")
            
            # STEP 1: First pass - parse [IMAGE ...] tags from speech_text into sketch_image actions
            # This creates sketch_image actions with metadata but no URLs yet
            timeline_data = generator._inject_sketch_image_actions(timeline_data, {})
            
            # Count how many sketch_image actions we need URLs for
            img_count = sum(
                1 for seg in timeline_data.get('segments', [])
                for act in seg.get('drawing_actions', [])
                if act.get('type') == 'sketch_image'
            )
            logger.info(f"Found {img_count} sketch_image actions needing URLs")
            
            # STEP 2: Research images for all sketch_image actions
            researched_images = _research_images_for_timeline(timeline_data, session.topic)
            
            # STEP 3: Second pass - inject researched URLs into sketch_image actions
            if researched_images:
                logger.info(f"Injecting {len(researched_images)} image URLs...")
                timeline_data = generator._inject_sketch_image_actions(timeline_data, researched_images)
            
            # Synthesize audio
            audio_pipeline = AudioSynthesisPipeline()
            timeline_data = audio_pipeline.synthesize_segments(timeline_data)
            audio_contents = timeline_data.pop('_audio_contents', {})
            
            # Save timeline
            timeline = Timeline.objects.create(
                session=session,
                segments=timeline_data['segments'],
                total_duration=timeline_data.get('total_actual_duration', 
                    timeline_data.get('total_estimated_duration', duration_target))
            )
            
            # Save segments
            for i, seg_data in enumerate(timeline_data['segments']):
                segment = TimelineSegment.objects.create(
                    timeline=timeline,
                    sequence_number=seg_data['sequence'],
                    start_time=seg_data['start_time'],
                    end_time=seg_data['end_time'],
                    speech_text=seg_data['speech_text'],
                    actual_audio_duration=seg_data.get('actual_audio_duration', seg_data.get('estimated_duration')),
                    drawing_actions=seg_data['drawing_actions']
                )
                
                if i in audio_contents:
                    audio_content = audio_contents[i]
                    filename = seg_data.get('audio_file', f"segment_{seg_data['sequence']}.mp3")
                    segment.audio_file.save(filename, ContentFile(audio_content), save=True)
                    seg_data['audio_file'] = segment.audio_file.url if segment.audio_file else None
            
            timeline.segments = timeline_data['segments']
            timeline.save()
            
            logger.info(f"Timeline {timeline.id} created")
            
            return Response({
                "timeline_id": timeline.id,
                "session_id": session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "status": "ready"
            }, status=201)
            
        except Exception as e:
            logger.error(f"Error: {e}", exc_info=True)
            return Response({"error": "Failed to generate timeline", "detail": str(e)}, status=500)


class GetTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request, timeline_id: int):
        try:
            timeline = Timeline.objects.get(pk=timeline_id)
            return Response({
                "timeline_id": timeline.id,
                "session_id": timeline.session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "created_at": timeline.created_at.isoformat()
            })
        except Timeline.DoesNotExist:
            return Response({"error": "Timeline not found"}, status=404)


class GetSessionTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request, session_id: int):
        try:
            session = get_object_or_404(LessonSession, pk=session_id)
            timeline = Timeline.objects.filter(session=session).order_by('-created_at').first()
            
            if not timeline:
                return Response({"error": "No timeline found"}, status=404)
            
            return Response({
                "timeline_id": timeline.id,
                "session_id": session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "created_at": timeline.created_at.isoformat()
            })
        except Exception as e:
            return Response({"error": str(e)}, status=500)
