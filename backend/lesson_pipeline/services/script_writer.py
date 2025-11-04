"""
Script writer service - wrapper around existing timeline_generator.
"""
import logging
import sys
from pathlib import Path
from typing import Optional

from lesson_pipeline.types import UserPrompt, ScriptDraft
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Add timeline_generator to path if needed
TIMELINE_GEN_DIR = Path(__file__).parent.parent.parent / 'timeline_generator'
if str(TIMELINE_GEN_DIR) not in sys.path:
    sys.path.insert(0, str(TIMELINE_GEN_DIR))


class ScriptWriterService:
    """Service for generating lesson scripts with IMAGE tags"""
    
    def __init__(self):
        try:
            from timeline_generator.services import TimelineGeneratorService
            self.timeline_service = TimelineGeneratorService()
            self.available = True
        except Exception as e:
            logger.error(f"Failed to load timeline generator: {e}")
            self.timeline_service = None
            self.available = False
    
    def generate_script(self, prompt: UserPrompt, duration_target: float = 60.0) -> ScriptDraft:
        """
        Generate a lesson script with IMAGE tags.
        
        Args:
            prompt: User prompt with lesson topic
            duration_target: Target duration in seconds
        
        Returns:
            ScriptDraft with content including [IMAGE ...] tags
        """
        if not self.available:
            logger.error("Timeline generator not available")
            return self._generate_fallback_script(prompt)
        
        try:
            logger.info(f"Generating script for: {prompt.text}")
            
            # Use existing timeline generator
            # Convert prompt to lesson_plan format expected by timeline generator
            lesson_plan = {
                'title': prompt.text,
                'steps': [prompt.text],  # Simple format
            }
            
            timeline_data = self.timeline_service.generate_timeline(
                lesson_plan=lesson_plan,
                topic=prompt.text,
                duration_target=duration_target
            )
            
            if not timeline_data or 'segments' not in timeline_data:
                logger.warning("Timeline generation returned invalid data")
                return self._generate_fallback_script(prompt)
            
            # Convert timeline segments to script content
            content = self._timeline_to_script(timeline_data, prompt.text)
            
            draft = ScriptDraft(
                prompt_id=prompt.id,
                content=content
            )
            
            logger.info(f"Generated script with {len(content)} characters")
            return draft
            
        except Exception as e:
            logger.error(f"Failed to generate script: {e}")
            return self._generate_fallback_script(prompt)
    
    def _timeline_to_script(self, timeline_data: dict, topic: str) -> str:
        """
        Convert timeline segments to script text with IMAGE tags.
        
        The timeline generator should already embed [IMAGE ...] tags in speech_text
        based on our updated system prompt.
        """
        segments = timeline_data.get('segments', [])
        
        # Build script from segments
        parts = []
        
        # Add title
        parts.append(f"# {topic}\n")
        
        for i, segment in enumerate(segments, 1):
            speech = segment.get('speech_text', '')
            
            # Add segment speech
            if speech:
                parts.append(f"{speech}\n")
            
            # Check if speech contains IMAGE tags - if not and this is a good spot, add one
            if i == 2 and '[IMAGE' not in speech:
                # Add an image early in the lesson
                parts.append(f'\n[IMAGE id="img_{i}" prompt="{topic} overview diagram" style="educational diagram" aspect="16:9"]\n')
            
        content = '\n'.join(parts)
        
        return content
    
    def _generate_fallback_script(self, prompt: UserPrompt) -> ScriptDraft:
        """Generate a simple fallback script"""
        logger.info("Generating fallback script")
        
        content = f"""# {prompt.text}

Today we'll learn about {prompt.text}.

[IMAGE id="img_1" prompt="{prompt.text} educational diagram" style="diagram" aspect="16:9"]

This is an important topic with many applications.

[IMAGE id="img_2" prompt="{prompt.text} real-world example" style="photo" aspect="16:9"]

Let's explore the key concepts and their practical uses.
"""
        
        return ScriptDraft(
            prompt_id=prompt.id,
            content=content
        )


# Global singleton
_script_writer_service: Optional[ScriptWriterService] = None


def get_script_writer_service() -> ScriptWriterService:
    """Get or create the global script writer service"""
    global _script_writer_service
    if _script_writer_service is None:
        _script_writer_service = ScriptWriterService()
    return _script_writer_service


# Convenience function
def generate_script(prompt: UserPrompt, duration_target: float = 60.0) -> ScriptDraft:
    """Generate a lesson script"""
    return get_script_writer_service().generate_script(prompt, duration_target)


