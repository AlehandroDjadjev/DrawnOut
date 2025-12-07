"""
Integration layer between timeline generation and lesson pipeline image system.

Extracts IMAGE tags from timeline segments and resolves them to actual images.
"""
import logging
import re
from typing import Dict, List, Optional

from lesson_pipeline.types import ImageTag, ResolvedImage, UserPrompt
from lesson_pipeline.utils.image_tags import parse_image_tags

logger = logging.getLogger(__name__)


def extract_image_tags_from_segments(segments: List[Dict]) -> List[Dict]:
    """
    Extract IMAGE tags from timeline segments and retain the parsed ImageTag objects.
    """
    image_tags: List[Dict[str, object]] = []
    seen_tags = set()
    
    for i, segment in enumerate(segments):
        speech_text = segment.get('speech_text', '')
        cleaned_text, tags = parse_image_tags(speech_text)
        
        for tag in tags:
            if tag.id in seen_tags:
                logger.warning(f"⚠️ Skipping duplicate IMAGE tag '{tag.id}' in segment {i+1}")
                continue
            
            placeholder = f'[[IMAGE:{tag.id}]]'
            placeholder_index = cleaned_text.find(placeholder)
            midpoint = len(cleaned_text) / 2 if cleaned_text else 0
            position = 'before_drawing' if 0 <= placeholder_index < midpoint else 'after_drawing'
            
            image_tags.append({
                'tag': tag,
                'segment_index': i,
                'position': position,
            })
            seen_tags.add(tag.id)
            logger.info(f"Found IMAGE tag '{tag.id}' in segment {i+1}: {tag.prompt[:50]}...")
        
        # Store cleaned speech text without placeholders for later TTS
        cleaned_no_placeholders = re.sub(r'\[\[IMAGE:[^\]]+\]\]', '', cleaned_text).strip()
        segment['speech_text'] = re.sub(r'\s+', ' ', cleaned_no_placeholders).strip()
    
    logger.info(f"✅ Extracted {len(image_tags)} unique IMAGE tags from {len(segments)} segments")
    return image_tags


def clean_speech_text_from_tags(speech_text: str) -> str:
    """Remove IMAGE placeholders from speech text so TTS doesn't read them"""
    cleaned = re.sub(r'\[\[IMAGE:[^\]]+\]\]', '', speech_text)
    return re.sub(r'\s+', ' ', cleaned).strip()


def resolve_images_for_timeline(topic: str, image_tags: List[Dict], subject: str = "General") -> Dict[str, ResolvedImage]:
    """
    Use the lesson pipeline to resolve image tags to actual image URLs.
    """
    try:
        logger.info(f"Resolving {len(image_tags)} images for topic: {topic}")
        
        parsed_tags: List[ImageTag] = [entry['tag'] for entry in image_tags if 'tag' in entry]
        if not parsed_tags:
            logger.warning("No tags parsed from synthetic script")
            return {}
        
        # Research and index images for the topic
        from lesson_pipeline.pipelines.image_ingestion import run_image_research_and_index_sync
        
        prompt = UserPrompt(text=topic)
        image_index_info = run_image_research_and_index_sync(
            prompt=prompt,
            subject=subject,
            max_images=40  # Research pool
        )
        
        topic_id = image_index_info.get('topic_id')
        if not topic_id:
            logger.error("No topic_id returned from image research")
            return {}
        
        logger.info(f"Indexed {image_index_info['indexed_count']} images for topic")
        
        # Resolve each tag to a base image
        from lesson_pipeline.pipelines.image_resolver import resolve_image_tags_for_topic
        
        resolved_base = resolve_image_tags_for_topic(topic_id, parsed_tags)
        
        if not resolved_base:
            logger.warning("No images resolved for tags")
            return {}
        
        logger.info(f"Resolved {len(resolved_base)} base images")
        
        # Transform images (or use base if ComfyUI unavailable)
        from lesson_pipeline.pipelines.image_transformation import transform_resolved_images
        
        resolved_images = transform_resolved_images(resolved_base)
        
        # Build mapping from tag_id to resolved payload
        tag_to_resolved: Dict[str, ResolvedImage] = {}
        for resolved in resolved_images:
            tag_id = resolved.tag.id  # Extract string ID from ImageTag object
            if resolved.final_image_url:
                tag_to_resolved[tag_id] = resolved
                logger.info(f"Resolved {tag_id} -> {resolved.final_image_url[:60]}...")
        
        logger.info(f"Successfully resolved {len(tag_to_resolved)} image URLs")
        return tag_to_resolved
        
    except Exception as e:
        logger.error(f"Failed to resolve images for timeline: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return {}


def inject_image_actions_into_segments(
    segments: List[Dict],
    image_tags: List[Dict],
    resolved_map: Dict[str, ResolvedImage]
) -> List[Dict]:
    """
    Add sketch_image drawing actions to segments based on resolved images.
    
    Args:
        segments: Timeline segments
        image_tags: Parsed image tags with segment_index and position
        tag_to_url: Mapping from tag_id to resolved image URL
    
    Returns:
        Modified segments with sketch_image actions added
    """
    logger.info(f"🖼️ Injecting images: {len(image_tags)} tags, {len(resolved_map)} resolved assets")
    for tag in image_tags:
        tag_obj: ImageTag = tag['tag']
        tag_id = tag_obj.id
        segment_idx = tag['segment_index']
        position = tag['position']
        
        resolved = resolved_map.get(tag_id)
        if not resolved or not resolved.final_image_url:
            logger.warning(f"No image payload found for tag {tag_id}, skipping")
            continue
        
        if segment_idx >= len(segments):
            logger.warning(f"Segment index {segment_idx} out of bounds for tag {tag_id}")
            continue
        
        segment = segments[segment_idx]
        drawing_actions = segment.get('drawing_actions', [])
        
        # Create sketch_image action
        # Note: Flutter DrawingAction expects 'text' and optionally 'level'
        # We'll store the image URL in 'text' and tag_id as a string in 'level'
        image_url = resolved.final_image_url
        placement = tag_obj.placement or {}
        notes = tag_obj.metadata.get('notes') if tag_obj.metadata else None

        image_action = {
            'type': 'sketch_image',
            'text': image_url,  # Image URL goes in 'text' field
            'level': hash(tag_id) % 1000,  # Store a numeric hash of tag_id
            'image_url': image_url,  # Also keep explicit field for reference
            'tag_id': tag_id,
            'prompt': tag_obj.prompt,
            'query': tag_obj.query or tag_obj.prompt,
            'vector_id': resolved.vector_id,
            'base_image_url': resolved.base_image_url,
            'placement': placement,
            'notes': notes,
            'style': {
                'aspect': tag_obj.aspect_ratio,
                'guidance': tag_obj.guidance_scale,
                'strength': tag_obj.strength,
            },
            'metadata': resolved.metadata,
        }
        
        logger.info(f"📦 Created image_action: type={image_action['type']}, url_length={len(image_url)}, url_preview={image_url[:100]}")
        
        # Insert based on position
        if position == 'before_drawing':
            # Insert at beginning
            drawing_actions.insert(0, image_action)
        else:
            # Append at end
            drawing_actions.append(image_action)
        
        segment['drawing_actions'] = drawing_actions
        logger.info(f"✅ Added sketch_image action for {tag_id} to segment {segment_idx + 1}, URL: {image_url[:80]}...")
    
    return segments


def process_timeline_with_images(timeline_data: Dict, topic: str, subject: str = "General") -> Dict:
    """
    Main entry point: process timeline to add resolved images.
    
    Args:
        timeline_data: Timeline dict with segments
        topic: Lesson topic
        subject: Subject area
    
    Returns:
        Modified timeline_data with:
        - IMAGE tags removed from speech_text
        - sketch_image actions added to segments
    """
    segments = timeline_data.get('segments', [])
    if not segments:
        logger.warning("No segments in timeline")
        return timeline_data
    
    # Extract image tags
    image_tags = extract_image_tags_from_segments(segments)
    
    if not image_tags:
        logger.warning("⚠️ No IMAGE tags found in timeline segments! Injecting default image...")
        
        # FALLBACK: Inject a default image tag in the middle segment
        middle_idx = len(segments) // 2
        if middle_idx < len(segments):
            default_tag = {
                'tag': ImageTag(
                    id='img_fallback',
                    prompt=f"educational diagram illustrating the main concepts of {topic}",
                    style='diagram',
                    aspect_ratio='16:9',
                    guidance_scale=7.5,
                    strength=0.7,
                    metadata={'notes': 'auto fallback placement'},
                ),
                'segment_index': middle_idx,
                'position': 'after_drawing',
            }
            image_tags.append(default_tag)
            logger.info(f"✅ Injected default image tag in segment {middle_idx + 1}")
        else:
            logger.warning("Cannot inject default image - no segments available")
            return timeline_data
    
    logger.info(f"Found {len(image_tags)} IMAGE tags in timeline")
    
    # Clean speech text (remove IMAGE tags so TTS doesn't read them)
    for segment in segments:
        original_speech = segment.get('speech_text', '')
        cleaned_speech = clean_speech_text_from_tags(original_speech)
        segment['speech_text'] = cleaned_speech
    
    # Resolve images using lesson pipeline
    resolved_map = resolve_images_for_timeline(topic, image_tags, subject)
    
    if not resolved_map:
        logger.warning("No images resolved, timeline will have no images")
        return timeline_data
    
    # Inject sketch_image actions into segments
    segments = inject_image_actions_into_segments(segments, image_tags, resolved_map)
    
    timeline_data['segments'] = segments
    timeline_data['image_count'] = len(resolved_map)
    
    logger.info(f"✅ Timeline processed with {len(resolved_map)} images integrated")
    
    return timeline_data

