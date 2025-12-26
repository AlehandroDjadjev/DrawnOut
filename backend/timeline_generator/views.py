"""API views for timeline generation"""
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


class GenerateTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request, session_id: int):
        """
        Generate a synchronized timeline for a lesson session
        
        POST /api/timeline/generate/<session_id>/
        Body: {
            "duration_target": 60.0,  # optional, default 60s
            "regenerate": false  # optional, force regeneration
        }
        
        Returns: {
            "timeline_id": 123,
            "segments": [...],
            "total_duration": 62.5,
            "status": "ready"
        }
        """
        try:
            session = LessonSession.objects.get(pk=session_id)
        except LessonSession.DoesNotExist:
            return Response({"error": "Session not found"}, status=404)
        
        # Check if timeline already exists
        regenerate = request.data.get('regenerate', False)
        if not regenerate:
            existing = Timeline.objects.filter(session=session).order_by('-created_at').first()
            if existing:
                logger.info(f"Using cached timeline {existing.id} for session {session_id}")
                return Response({
                    "timeline_id": existing.id,
                    "session_id": session.id,
                    "segments": existing.segments,
                    "total_duration": existing.total_duration,
                    "status": "cached"
                })
        
        # Generate new timeline
        duration_target = float(request.data.get('duration_target', 60.0))
        
        logger.info(f"Generating new timeline for session {session_id}, target duration: {duration_target}s")
        
        try:
            generator = TimelineGeneratorService()
            logger.info(f"Generating timeline for session {session_id}, topic: {session.topic}")
            timeline_data = generator.generate_timeline(
                lesson_plan={'lesson_plan': session.lesson_plan},
                topic=session.topic,
                duration_target=duration_target
            )
            
            if not timeline_data:
                logger.error("Timeline generator returned None")
                return Response({
                    "error": "Failed to generate timeline"
                }, status=500)
            
            logger.info(f"Timeline generated with {len(timeline_data.get('segments', []))} segments")
            
            # Synthesize audio for segments
            logger.info("Synthesizing audio for segments...")
            audio_pipeline = AudioSynthesisPipeline()
            timeline_data = audio_pipeline.synthesize_segments(timeline_data)
            
            # Extract audio contents (stored separately to avoid JSON serialization issues)
            audio_contents = timeline_data.pop('_audio_contents', {})
            
            # Save timeline
            timeline = Timeline.objects.create(
                session=session,
                segments=timeline_data['segments'],
                total_duration=timeline_data.get(
                    'total_actual_duration', 
                    timeline_data.get('total_estimated_duration', duration_target)
                )
            )
            
            # Save individual segment records with audio files
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
                
                # Save audio file if available
                if i in audio_contents:
                    audio_content = audio_contents[i]
                    filename = seg_data.get('audio_file', f'segment_{seg_data["sequence"]}.mp3')
                    segment.audio_file.save(
                        filename,
                        ContentFile(audio_content),
                        save=True
                    )
                    # Update segments data with actual file path
                    seg_data['audio_file'] = segment.audio_file.url if segment.audio_file else None
            
            # Update timeline with file URLs
            timeline.segments = timeline_data['segments']
            timeline.save()
            
            logger.info(f"Timeline {timeline.id} created successfully with {len(timeline_data['segments'])} segments")
            
            return Response({
                "timeline_id": timeline.id,
                "session_id": session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "status": "ready"
            }, status=201)
            
        except Exception as e:
            logger.error(f"Error generating timeline: {e}", exc_info=True)
            return Response({
                "error": "Failed to generate timeline",
                "detail": str(e)
            }, status=500)


class GetTimelineView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request, timeline_id: int):
        """Get timeline by ID"""
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
        """Get the latest timeline for a session"""
        try:
            session = get_object_or_404(LessonSession, pk=session_id)
            timeline = Timeline.objects.filter(session=session).order_by('-created_at').first()
            
            if not timeline:
                return Response({
                    "error": "No timeline found for this session"
                }, status=404)
            
            return Response({
                "timeline_id": timeline.id,
                "session_id": session.id,
                "segments": timeline.segments,
                "total_duration": timeline.total_duration,
                "created_at": timeline.created_at.isoformat()
            })
        except Exception as e:
            return Response({
                "error": str(e)
            }, status=500)

