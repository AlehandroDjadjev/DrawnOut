"""
Script writer service - wrapper around existing timeline_generator.
"""
import logging
import sys
from pathlib import Path
from typing import Optional, List

from lesson_pipeline.types import UserPrompt, ScriptDraft
from lesson_pipeline.config import config
from lesson_pipeline.utils.image_tags import count_image_tags

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
        
        tag_sequence = 0
        
        for i, segment in enumerate(segments, 1):
            speech = segment.get('speech_text', '')
            
            # Add segment speech
            if speech:
                parts.append(f"{speech}\n")
            
            tag_lines = self._build_image_tags_for_segment(
                segment=segment,
                topic=topic,
                sequence_index=i,
                tag_sequence_start=tag_sequence,
            )
            tag_sequence += len(tag_lines)
            parts.extend(tag_lines)
            
        content = '\n'.join(parts)
        
        # Guarantee at least two IMAGE tags for downstream tooling
        existing_tag_count = count_image_tags(content)
        if existing_tag_count < 2:
            needed = 2 - existing_tag_count
            fallback_start = segments[0].get('start_time', 0.0) if segments else 0.0
            for idx in range(needed):
                fallback_tag = self._format_image_tag(
                    tag_id=f"img_auto_{tag_sequence + idx + 1}",
                    prompt=f"{topic} educational diagram #{idx + 1}",
                    query=f"{topic} educational diagram #{idx + 1}",
                    style="diagram",
                    aspect="16:9",
                    time_offset=fallback_start + 8 * (idx + 1),
                    duration=6.0,
                    layout=None,
                    notes="auto-generated fallback slot",
                )
                parts.append(fallback_tag)
            content = '\n'.join(parts)
        
        return content
    
    def _build_image_tags_for_segment(
        self,
        segment: dict,
        topic: str,
        sequence_index: int,
        tag_sequence_start: int,
    ) -> List[str]:
        """Create IMAGE tags based on drawing actions for a timeline segment."""
        drawing_actions = segment.get('drawing_actions', []) or []
        if not drawing_actions:
            return []
        
        tag_lines: List[str] = []
        start_time = float(segment.get('start_time', sequence_index * 8.0))
        duration = float(segment.get('estimated_duration', 6.0))
        
        for offset, action in enumerate(drawing_actions):
            if (action or {}).get('type') != 'sketch_image':
                continue
            
            tag_id = action.get('tag_id') or f"img_{sequence_index}_{tag_sequence_start + offset + 1}"
            prompt = action.get('prompt') or f"{topic} educational illustration"
            query = action.get('query') or prompt
            style = action.get('style') or 'diagram'
            aspect = action.get('aspect') or '16:9'
            layout = action.get('layout')
            notes = action.get('notes') or action.get('text')
            
            tag_lines.append(
                self._format_image_tag(
                    tag_id=tag_id,
                    prompt=prompt,
                    query=query,
                    style=style,
                    aspect=aspect,
                    time_offset=start_time,
                    duration=duration,
                    layout=layout,
                    notes=notes,
                )
            )
        
        return tag_lines
    
    def _format_image_tag(
        self,
        tag_id: str,
        prompt: str,
        query: str | None,
        style: str,
        aspect: str,
        time_offset: float,
        duration: float,
        layout: dict | str | None,
        notes: str | None = None,
    ) -> str:
        """Format an IMAGE tag string with sanitized attributes."""
        attrs = [
            f'id="{self._sanitize_attr(tag_id)}"',
            f'prompt="{self._sanitize_attr(prompt)}"',
            f'query="{self._sanitize_attr(query or prompt)}"',
            f'style="{self._sanitize_attr(style)}"',
            f'aspect="{self._sanitize_attr(aspect)}"',
            f'time="{round(time_offset, 2)}s"',
            f'duration="{round(duration, 2)}s"',
        ]
        
        layout_str = self._serialize_layout(layout)
        if layout_str:
            attrs.append(f'layout="{self._sanitize_attr(layout_str)}"')

        layout_dict = layout if isinstance(layout, dict) else {}
        if isinstance(layout_dict, dict):
            for axis in ('x', 'y', 'width', 'height', 'scale'):
                axis_value = layout_dict.get(axis)
                if axis_value is not None:
                    attrs.append(f'{axis}="{self._format_decimal(axis_value)}"')
        
        if notes:
            attrs.append(f'notes="{self._sanitize_attr(notes)}"')
        
        return f"[IMAGE {' '.join(attrs)}]"
    
    @staticmethod
    def _sanitize_attr(value: str | None) -> str:
        if value is None:
            return ''
        return str(value).replace('"', "'").strip()
    
    @staticmethod
    def _serialize_layout(layout: dict | str | None) -> str:
        if layout is None:
            return ''
        if isinstance(layout, str):
            return layout
        if isinstance(layout, dict):
            ordered_keys = ['x', 'y', 'width', 'height', 'scale']
            segments = []
            for key in ordered_keys:
                if key in layout and layout[key] is not None:
                    segments.append(f"{key}:{layout[key]}")
            return ','.join(segments)
        return ''
    
    @staticmethod
    def _format_decimal(value: float | int | str) -> str:
        try:
            return f"{float(value):.4f}".rstrip('0').rstrip('.') or "0"
        except (TypeError, ValueError):
            return str(value)
    
    def _generate_fallback_script(self, prompt: UserPrompt) -> ScriptDraft:
        """Generate a simple fallback script"""
        logger.info("Generating fallback script")
        
        content = f"""# {prompt.text}

Today we'll learn about {prompt.text}.

[IMAGE id="img_1" prompt="{prompt.text} educational diagram" query="{prompt.text} overview" style="diagram" aspect="16:9" time="8s" duration="6s" x="0.08" y="0.12" width="0.4" height="0.5" notes="Anchor left column"]

This is an important topic with many applications.

[IMAGE id="img_2" prompt="{prompt.text} real-world example" query="{prompt.text} application" style="photo" aspect="16:9" time="24s" duration="6s" x="0.52" y="0.15" width="0.38" height="0.48" notes="Balance on right"]

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









