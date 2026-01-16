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
                
                # Validate timeline structure
                if not self._validate_timeline(timeline_data):
                    logger.warning(f"Invalid timeline structure on attempt {attempt + 1}")
                    if attempt < max_retries - 1:
                        continue
                    raise ValueError("Invalid timeline structure after all retries")
                
                # Add cumulative timings
                timeline_data = self._compute_cumulative_timings(timeline_data)
                
                # NOTE: Don't inject sketch_image actions here - it's done in views.py
                # after image research completes so we have actual image URLs
                
                logger.info(f"Successfully generated timeline with {len(timeline_data['segments'])} segments")
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

        # Optional image_requests contract
        if 'image_requests' in data and data['image_requests'] is not None:
            image_requests = data['image_requests']
            if not isinstance(image_requests, list):
                logger.warning("image_requests must be a list if provided")
                return False
            for req in image_requests:
                if not self._validate_image_request(req):
                    logger.warning(f"Invalid image_request: {req}")
                    return False
        
        return True

    @staticmethod
    def _validate_image_request(req: dict) -> bool:
        """Validate optional image request entries (best-effort, non-fatal)."""
        if not isinstance(req, dict):
            return False
        if 'prompt' not in req or not isinstance(req.get('prompt'), str):
            return False
        placement = req.get('placement')
        if placement is not None:
            if not isinstance(placement, dict):
                return False
            for key in ('x', 'y', 'width', 'height'):
                if key not in placement:
                    return False
                try:
                    float(placement[key])
                except (TypeError, ValueError):
                    return False
            if 'scale' in placement:
                try:
                    float(placement['scale'])
                except (TypeError, ValueError):
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

    def _inject_sketch_image_actions(self, data: dict, researched_images: Optional[Dict[str, dict]] = None) -> dict:
        """
        Convert image_requests into sketch_image drawing actions and populate URLs.
        
        This method:
        1. Parses [IMAGE ...] tags from speech_text
        2. Creates sketch_image actions from image_requests
        3. Updates existing sketch_image actions with researched URLs
        
        Args:
            data: Timeline data with segments and optional image_requests
            researched_images: Dict mapping image id -> {url, metadata, ...}
        
        Returns:
            Modified timeline data with sketch_image actions injected
        """
        import re
        
        if researched_images is None:
            researched_images = {}
        
        # Build lookup from image_requests
        image_requests_map = {}
        image_requests = data.get('image_requests', [])
        for req in image_requests:
            img_id = req.get('id', '')
            if img_id:
                image_requests_map[img_id] = req
        
        # Pattern to match [IMAGE ...] tags in speech_text
        image_tag_pattern = re.compile(
            r'\[IMAGE\s+([^\]]+)\]',
            re.IGNORECASE
        )
        
        for segment in data['segments']:
            speech_text = segment.get('speech_text', '')
            
            # First: Update any existing sketch_image actions with researched URLs
            if 'drawing_actions' in segment:
                for action in segment['drawing_actions']:
                    if action.get('type') == 'sketch_image':
                        # Get the image ID from metadata
                        metadata = action.get('metadata', {})
                        img_id = metadata.get('id', '')
                        
                        # Check if we have researched image data for this ID
                        if img_id and img_id in researched_images:
                            img_data = researched_images[img_id]
                            url = img_data.get('url') or img_data.get('image_url')
                            if url:
                                action['image_url'] = url
                                logger.info(f"Updated sketch_image '{img_id}' with URL: {url[:60]}...")
                        
                        # If still no URL, check by prompt matching as fallback
                        if not action.get('image_url'):
                            prompt = metadata.get('prompt', '') or action.get('text', '')
                            for rid, rdata in researched_images.items():
                                if rdata.get('prompt') == prompt:
                                    url = rdata.get('url') or rdata.get('image_url')
                                    if url:
                                        action['image_url'] = url
                                        logger.info(f"Updated sketch_image by prompt match with URL: {url[:60]}...")
                                        break
            
            # Second: Find all IMAGE tags in speech and create new actions
            for match in image_tag_pattern.finditer(speech_text):
                full_tag = match.group(0)
                attrs_str = match.group(1)
                
                # Parse attributes from tag
                attrs = self._parse_image_tag_attrs(attrs_str)
                img_id = attrs.get('id', f'img_{len(segment.get("drawing_actions", []))+1}')
                
                # Get researched image data or fallback to image_requests
                img_data = researched_images.get(img_id, image_requests_map.get(img_id, {}))
                image_url = img_data.get('url') or img_data.get('image_url')
                
                # Build placement from tag attributes (normalized 0..1)
                placement = None
                if any(k in attrs for k in ['x', 'y', 'width', 'height']):
                    try:
                        # Convert normalized (0-1) to pixel coordinates
                        # Assume 1920x1080 canvas for now, frontend can adjust
                        canvas_w, canvas_h = 1920, 1080
                        placement = {
                            'x': float(attrs.get('x', 0.1)) * canvas_w,
                            'y': float(attrs.get('y', 0.1)) * canvas_h,
                            'width': float(attrs.get('width', 0.4)) * canvas_w,
                            'height': float(attrs.get('height', 0.4)) * canvas_h,
                        }
                        if 'scale' in attrs:
                            placement['scale'] = float(attrs['scale'])
                    except (ValueError, TypeError):
                        placement = None
                
                # Use placement from image_requests if not in tag
                if not placement and img_data.get('placement'):
                    try:
                        req_placement = img_data['placement']
                        canvas_w, canvas_h = 1920, 1080
                        placement = {
                            'x': float(req_placement.get('x', 0.1)) * canvas_w,
                            'y': float(req_placement.get('y', 0.1)) * canvas_h,
                            'width': float(req_placement.get('width', 0.4)) * canvas_w,
                            'height': float(req_placement.get('height', 0.4)) * canvas_h,
                        }
                        if 'scale' in req_placement:
                            placement['scale'] = float(req_placement['scale'])
                    except (ValueError, TypeError):
                        pass
                
                # Create sketch_image action
                sketch_action = {
                    'type': 'sketch_image',
                    'text': attrs.get('prompt', '')[:100],  # Alt text
                    'image_url': image_url,
                    'placement': placement,
                    'metadata': {
                        'id': img_id,
                        'query': attrs.get('query', ''),
                        'prompt': attrs.get('prompt', ''),
                        'style': attrs.get('style', img_data.get('style', 'diagram')),
                        'notes': attrs.get('notes', ''),
                        'source': img_data.get('source', 'unknown'),
                    }
                }
                
                # Add to drawing_actions
                if 'drawing_actions' not in segment:
                    segment['drawing_actions'] = []
                segment['drawing_actions'].append(sketch_action)
                
                logger.info(f"Injected sketch_image action: id={img_id}, url={image_url is not None}")
            
            # Third: Create sketch_image actions from image_requests that weren't in tags
            # Match them to segments based on sequence or insert in appropriate positions
            # For now, we'll add any unmatched image_requests to segments that don't have images
            
            # Remove IMAGE tags from speech_text (they shouldn't be spoken)
            segment['speech_text'] = image_tag_pattern.sub('', speech_text).strip()
            # Clean up double spaces
            segment['speech_text'] = re.sub(r'\s+', ' ', segment['speech_text'])
        
        # Fourth: Process image_requests that haven't been added yet
        # These are images requested but not associated with [IMAGE] tags in speech
        segments_with_images = set()
        for segment in data['segments']:
            for action in segment.get('drawing_actions', []):
                if action.get('type') == 'sketch_image':
                    img_id = action.get('metadata', {}).get('id', '')
                    if img_id:
                        segments_with_images.add(img_id)
        
        unmatched_requests = [req for req in image_requests if req.get('id') not in segments_with_images]
        
        if unmatched_requests:
            logger.info(f"Processing {len(unmatched_requests)} unmatched image_requests...")
            
            # Distribute unmatched images across segments (prefer segments 2-4)
            target_sequences = [2, 3, 4, 5, 6]
            
            for i, req in enumerate(unmatched_requests):
                img_id = req.get('id', f'img_{i+1}')
                img_data = researched_images.get(img_id, {})
                image_url = img_data.get('url') or img_data.get('image_url')
                
                # Build placement
                placement = None
                if req.get('placement'):
                    try:
                        req_placement = req['placement']
                        canvas_w, canvas_h = 1920, 1080
                        placement = {
                            'x': float(req_placement.get('x', 0.1)) * canvas_w,
                            'y': float(req_placement.get('y', 0.1)) * canvas_h,
                            'width': float(req_placement.get('width', 0.4)) * canvas_w,
                            'height': float(req_placement.get('height', 0.4)) * canvas_h,
                        }
                    except (ValueError, TypeError):
                        pass
                
                sketch_action = {
                    'type': 'sketch_image',
                    'text': req.get('prompt', '')[:100],
                    'image_url': image_url,
                    'placement': placement,
                    'metadata': {
                        'id': img_id,
                        'query': req.get('query', ''),
                        'prompt': req.get('prompt', ''),
                        'style': req.get('style', 'diagram'),
                        'notes': req.get('notes', ''),
                        'source': img_data.get('source', 'unknown'),
                    }
                }
                
                # Find target segment
                target_seq = target_sequences[i % len(target_sequences)]
                for segment in data['segments']:
                    if segment.get('sequence') == target_seq:
                        if 'drawing_actions' not in segment:
                            segment['drawing_actions'] = []
                        segment['drawing_actions'].append(sketch_action)
                        logger.info(f"Added unmatched image_request '{img_id}' to segment {target_seq}, url={image_url is not None}")
                        break
        
        return data

    def _parse_image_tag_attrs(self, attrs_str: str) -> Dict[str, str]:
        """Parse key="value" attributes from IMAGE tag string"""
        import re
        attrs = {}
        attr_pattern = re.compile(r'(\w+)="([^"]*)"')
        for match in attr_pattern.finditer(attrs_str):
            key, value = match.groups()
            attrs[key.lower()] = value
        return attrs
    
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

