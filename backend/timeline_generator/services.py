"""Services for timeline generation and audio synthesis"""
import os
import json
import time
import logging
from typing import Dict, List, Optional
from django.core.files.base import ContentFile

logger = logging.getLogger(__name__)


class TimelineGeneratorService:
    """Generates synchronized speech-drawing timelines using OpenAI GPT-4"""
    
    def __init__(self):
        try:
            from openai import OpenAI
            api_key = os.getenv('OPENAI_API_KEY')
            if not api_key:
                raise ValueError("OPENAI_API_KEY not set")
            self.client = OpenAI(api_key=api_key)
            self.model = "gpt-4o"  # Latest model with structured outputs
        except Exception as e:
            logger.error(f"Failed to initialize OpenAI client: {e}")
            self.client = None
            self.model = None
    
    def generate_timeline(
        self,
        lesson_plan: dict,
        topic: str,
        duration_target: float = 60.0,
        max_retries: int = 3
    ) -> Optional[Dict]:
        """
        Generate a synchronized timeline using GPT-4
        
        Args:
            lesson_plan: Dictionary with lesson content
            topic: Lesson topic string
            duration_target: Target duration in seconds
            max_retries: Number of retry attempts
        
        Returns:
            {
                "segments": [...],
                "total_estimated_duration": float,
                "metadata": {...}
            }
        """
        if not self.client:
            logger.error("OpenAI client not initialized")
            return self._generate_fallback_timeline(lesson_plan, topic, duration_target)
        
        from .prompts import TIMELINE_GENERATION_SYSTEM_PROMPT, build_timeline_prompt
        
        user_prompt = build_timeline_prompt(lesson_plan, topic, duration_target)
        
        for attempt in range(max_retries):
            try:
                logger.info(f"Generating timeline attempt {attempt + 1}/{max_retries}")
                
                response = self.client.chat.completions.create(
                    model=self.model,
                    messages=[
                        {"role": "system", "content": TIMELINE_GENERATION_SYSTEM_PROMPT},
                        {"role": "user", "content": user_prompt}
                    ],
                    response_format={"type": "json_object"},
                    temperature=0.7,
                    max_tokens=4000,
                )
                
                content = response.choices[0].message.content
                timeline_data = json.loads(content)
                
                # Debug: Check for IMAGE tags in speech_text
                image_tag_count = 0
                for seg in timeline_data.get('segments', []):
                    speech = seg.get('speech_text', '')
                    if '[IMAGE' in speech:
                        image_tag_count += 1
                        logger.debug(f"✅ Segment {seg.get('sequence', '?')} has IMAGE tag")
                logger.info(f"📊 Timeline has {image_tag_count} segments with IMAGE tags")
                
                # ENFORCE: Must have at least 1 IMAGE tag (ideally 3)
                if image_tag_count == 0:
                    logger.warning(f"⚠️ Timeline has NO IMAGE tags! Retrying... (attempt {attempt + 1}/{max_retries})")
                    if attempt < max_retries - 1:
                        continue  # Retry
                    else:
                        logger.error("❌ Failed to generate timeline with IMAGE tags after all retries")
                        # Continue anyway rather than failing completely
                
                # Validate timeline structure
                if not self._validate_timeline(timeline_data):
                    logger.warning(f"Invalid timeline structure on attempt {attempt + 1}")
                    if attempt < max_retries - 1:
                        continue
                    raise ValueError("Invalid timeline structure after all retries")
                
                # Add cumulative timings
                timeline_data = self._compute_cumulative_timings(timeline_data)
                
                logger.info(f"Successfully generated timeline with {len(timeline_data['segments'])} segments")
                
                # Process images if any IMAGE tags present
                try:
                    from .image_integration import process_timeline_with_images
                    logger.info("🎨 Processing timeline images...")
                    timeline_data = process_timeline_with_images(
                        timeline_data, 
                        topic=topic,
                        subject="General"  # Could be passed as parameter
                    )
                    logger.info(f"✅ Image processing complete. Image count: {timeline_data.get('image_count', 0)}")
                except Exception as e:
                    logger.error(f"❌ Failed to process images for timeline: {e}")
                    import traceback
                    logger.error(traceback.format_exc())
                    # Continue without images
                
                return timeline_data
                
            except Exception as e:
                logger.error(f"Timeline generation attempt {attempt + 1} failed: {e}")
                if attempt == max_retries - 1:
                    logger.warning("All attempts failed, using fallback timeline")
                    return self._generate_fallback_timeline(lesson_plan, topic, duration_target)
                time.sleep(1)
        
        return None
    
    def _validate_timeline(self, data: dict) -> bool:
        """Validate timeline structure"""
        if not isinstance(data, dict):
            return False
        if 'segments' not in data:
            return False
        segments = data['segments']
        if not isinstance(segments, list) or len(segments) == 0:
            return False
        
        for seg in segments:
            required = ['sequence', 'speech_text', 'estimated_duration', 'drawing_actions']
            if not all(k in seg for k in required):
                logger.warning(f"Segment missing required fields: {seg}")
                return False
            if not isinstance(seg['drawing_actions'], list):
                return False
        
        return True
    
    def _compute_cumulative_timings(self, data: dict) -> dict:
        """Add start_time and end_time to each segment"""
        cumulative = 0.0
        for segment in data['segments']:
            segment['start_time'] = round(cumulative, 2)
            duration = segment.get('estimated_duration', 3.0)
            cumulative += duration
            segment['end_time'] = round(cumulative, 2)
        
        data['total_estimated_duration'] = round(cumulative, 2)
        return data
    
    def _generate_fallback_timeline(
        self, 
        lesson_plan: dict, 
        topic: str, 
        duration_target: float
    ) -> Dict:
        """Generate a simple fallback timeline when GPT-4 fails"""
        logger.info("Generating fallback timeline")
        
        steps = lesson_plan.get('steps', lesson_plan.get('lesson_plan', []))
        if isinstance(steps, str):
            steps = [steps]
        elif not isinstance(steps, list):
            steps = [f"Introduction to {topic}"]
        
        segments = []
        segment_duration = max(3.0, duration_target / max(len(steps), 1))
        
        # Topic heading
        segments.append({
            "sequence": 1,
            "speech_text": f"Let's learn about {topic}",
            "estimated_duration": 3.0,
            "drawing_actions": [
                {"type": "heading", "text": topic.upper()}
            ]
        })
        
        # Add steps as bullet points
        for i, step in enumerate(steps[:10]):  # Max 10 steps
            segments.append({
                "sequence": i + 2,
                "speech_text": str(step),
                "estimated_duration": min(segment_duration, 8.0),
                "drawing_actions": [
                    {"type": "bullet", "text": str(step)[:80], "level": 1}
                ]
            })
        
        timeline = {"segments": segments}
        timeline = self._compute_cumulative_timings(timeline)
        
        return timeline


class AudioSynthesisPipeline:
    """Synthesizes audio for each timeline segment"""
    
    def __init__(self):
        try:
            from google.cloud import texttospeech
            self.tts_client = texttospeech.TextToSpeechClient()
            self.tts_available = True
        except Exception as e:
            logger.error(f"Google TTS client initialization failed: {e}")
            self.tts_client = None
            self.tts_available = False
    
    def synthesize_segments(self, timeline: Dict) -> Dict:
        """
        Synthesize audio for all segments and update with actual durations
        
        Returns timeline with audio_file and actual_audio_duration added to each segment.
        Audio content is stored separately and NOT in the timeline dict to avoid JSON serialization errors.
        """
        if not self.tts_available:
            logger.warning("TTS not available, using estimated durations")
            # Just use estimated durations without audio
            for seg in timeline['segments']:
                seg['actual_audio_duration'] = seg.get('estimated_duration', 3.0)
                seg['audio_file'] = None
            return timeline
        
        segments = timeline['segments']
        audio_contents = {}  # Store audio separately, keyed by segment index
        
        for i, segment in enumerate(segments):
            try:
                # Synthesize audio
                audio_content = self._synthesize_speech(segment['speech_text'])
                
                # Get actual duration
                duration = self._get_audio_duration_from_bytes(audio_content)
                
                # If we got placeholder (3.0), estimate from text instead
                if duration == 3.0:
                    duration = self._estimate_duration_from_text(segment['speech_text'])
                    logger.info(f"Using text-based duration estimate: {duration:.2f}s")
                
                segment['actual_audio_duration'] = round(duration, 2)
                
                # Save audio file name
                filename = f"segment_{i+1}_{int(time.time())}_{i}.mp3"
                segment['audio_file'] = filename
                
                # Store audio content separately (NOT in segment dict)
                audio_contents[i] = audio_content
                
                logger.info(f"Synthesized segment {i+1}: {duration:.2f}s")
                
            except Exception as e:
                logger.error(f"Failed to synthesize segment {i+1}: {e}")
                # Use text-based estimation as fallback
                duration = self._estimate_duration_from_text(segment.get('speech_text', ''))
                segment['actual_audio_duration'] = duration
                segment['audio_file'] = None
        
        # Recompute timings based on actual durations
        timeline = self._recompute_timings(timeline)
        
        # Store audio contents separately for the view to access
        timeline['_audio_contents'] = audio_contents
        
        return timeline
    
    def _synthesize_speech(self, text: str) -> bytes:
        """Synthesize speech using Google Cloud TTS"""
        from google.cloud import texttospeech
        
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-F"  # Female voice
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=1.0,
            pitch=0.0,
        )
        
        response = self.tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config
        )
        
        return response.audio_content
    
    def _get_audio_duration_from_bytes(self, audio_bytes: bytes) -> float:
        """Get duration of audio in seconds from bytes"""
        try:
            # Try mutagen (lightweight, no external dependencies)
            import io
            from mutagen.mp3 import MP3
            
            audio_io = io.BytesIO(audio_bytes)
            audio = MP3(audio_io)
            return audio.info.length
        except Exception:
            pass
        
        try:
            # Try pydub as fallback
            import io
            from pydub import AudioSegment
            
            audio = AudioSegment.from_mp3(io.BytesIO(audio_bytes))
            duration = len(audio) / 1000.0
            return duration
        except Exception:
            pass
        
        # Final fallback: estimate from text length
        # Google TTS speaks at ~150 words per minute = 2.5 words/sec
        # This is just for getting a duration estimate from the speech_text
        logger.warning("Could not determine audio duration from bytes, will use text-based estimate")
        return 3.0  # Return placeholder, will be calculated from text in calling code
    
    def _estimate_duration_from_text(self, text: str) -> float:
        """Estimate speech duration from text (words per minute method)"""
        words = len(text.split())
        # Average: 150 words per minute = 2.5 words per second
        duration = words / 2.5
        # Add small pause at end
        duration += 0.3
        return round(max(2.0, duration), 1)
    
    def _recompute_timings(self, timeline: Dict) -> Dict:
        """Recompute start/end times based on actual audio durations"""
        cumulative = 0.0
        for segment in timeline['segments']:
            segment['start_time'] = round(cumulative, 2)
            duration = segment.get('actual_audio_duration', segment.get('estimated_duration', 3.0))
            cumulative += duration
            segment['end_time'] = round(cumulative, 2)
        
        timeline['total_actual_duration'] = round(cumulative, 2)
        return timeline

