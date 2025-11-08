"""
Utilities for parsing and handling IMAGE tags in lesson scripts.
"""
import re
from typing import List, Tuple, Dict
from lesson_pipeline.types import ImageTag, ResolvedImage


# Regex to match [IMAGE ...] tags
IMAGE_TAG_PATTERN = re.compile(
    r'\[IMAGE\s+'
    r'(?:id="([^"]+)"\s+)?'
    r'(?:prompt="([^"]+)"\s*)?'
    r'(?:style="([^"]+)"\s*)?'
    r'(?:aspect="([^"]+)"\s*)?'
    r'(?:size="([^"]+)"\s*)?'
    r'(?:strength="([^"]+)"\s*)?'
    r'(?:guidance="([^"]+)"\s*)?'
    r'\]',
    re.IGNORECASE
)

# More flexible pattern that handles attributes in any order
FLEXIBLE_IMAGE_TAG_PATTERN = re.compile(
    r'\[IMAGE\s+([^\]]+)\]',
    re.IGNORECASE
)


def parse_image_tags(content: str) -> Tuple[str, List[ImageTag]]:
    """
    Parse IMAGE tags from content.
    
    Args:
        content: Script content with [IMAGE ...] tags
    
    Returns:
        Tuple of (cleaned_content, tags) where:
        - cleaned_content has tags replaced with [[IMAGE:id]] placeholders
        - tags is a list of parsed ImageTag objects
    
    Example:
        Input: "Text [IMAGE id=\"img_1\" prompt=\"a cat\" style=\"photo\"] more text"
        Output: ("Text [[IMAGE:img_1]] more text", [ImageTag(...)])
    """
    tags: List[ImageTag] = []
    cleaned_content = content
    
    # Find all IMAGE tags
    for match in FLEXIBLE_IMAGE_TAG_PATTERN.finditer(content):
        full_tag = match.group(0)
        attributes_str = match.group(1)
        
        # Parse attributes
        attrs = _parse_attributes(attributes_str)
        
        # Create ImageTag
        tag_id = attrs.get('id', f'img_{len(tags) + 1}')
        tag = ImageTag(
            id=tag_id,
            prompt=attrs.get('prompt', ''),
            style=attrs.get('style'),
            aspect_ratio=attrs.get('aspect'),
            size=attrs.get('size'),
            guidance_scale=_parse_float(attrs.get('guidance'), 7.5),
            strength=_parse_float(attrs.get('strength'), 0.7),
        )
        
        tags.append(tag)
        
        # Replace tag with placeholder
        placeholder = f'[[IMAGE:{tag_id}]]'
        cleaned_content = cleaned_content.replace(full_tag, placeholder, 1)
    
    return cleaned_content, tags


def _parse_attributes(attr_str: str) -> Dict[str, str]:
    """Parse key="value" attributes from string"""
    attrs = {}
    # Match key="value" pairs
    attr_pattern = re.compile(r'(\w+)="([^"]*)"')
    for match in attr_pattern.finditer(attr_str):
        key, value = match.groups()
        attrs[key.lower()] = value
    return attrs


def _parse_float(value: str | None, default: float) -> float:
    """Parse float value with fallback"""
    if value is None:
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def inject_resolved_images(
    content_with_placeholders: str,
    images: List[ResolvedImage]
) -> str:
    """
    Replace [[IMAGE:id]] placeholders with actual image references.
    
    Args:
        content_with_placeholders: Content with [[IMAGE:id]] tokens
        images: List of resolved images
    
    Returns:
        Content with placeholders replaced by markdown image syntax
    
    Example:
        Input: "Text [[IMAGE:img_1]] more text"
        Output: "Text ![a cat](https://...final_url){.lesson-image} more text"
    """
    result = content_with_placeholders
    
    for resolved in images:
        placeholder = f'[[IMAGE:{resolved.tag.id}]]'
        
        # Create markdown image with alt text and URL
        # Format: ![alt text](url){.class data-attr="value"}
        alt_text = resolved.tag.prompt[:100]  # Truncate if too long
        img_url = resolved.final_image_url
        
        # Add metadata as data attributes
        metadata_attrs = []
        if resolved.tag.style:
            metadata_attrs.append(f'data-style="{resolved.tag.style}"')
        if resolved.tag.aspect_ratio:
            metadata_attrs.append(f'data-aspect="{resolved.tag.aspect_ratio}"')
        if resolved.base_image_url:
            metadata_attrs.append(f'data-base-url="{resolved.base_image_url}"')
        
        attrs_str = ' '.join(metadata_attrs)
        
        # Markdown format: ![alt](url){.class attrs}
        image_markdown = f'![{alt_text}]({img_url}){{.lesson-image {attrs_str}}}'
        
        result = result.replace(placeholder, image_markdown)
    
    return result


def count_image_tags(content: str) -> int:
    """Count number of IMAGE tags in content"""
    return len(FLEXIBLE_IMAGE_TAG_PATTERN.findall(content))


def validate_image_tag(tag: ImageTag) -> List[str]:
    """
    Validate an ImageTag and return list of errors.
    
    Returns:
        Empty list if valid, list of error messages if invalid
    """
    errors = []
    
    if not tag.id:
        errors.append("Image tag missing 'id'")
    
    if not tag.prompt:
        errors.append(f"Image tag '{tag.id}' missing 'prompt'")
    
    if tag.aspect_ratio and not _is_valid_aspect_ratio(tag.aspect_ratio):
        errors.append(f"Invalid aspect ratio '{tag.aspect_ratio}' for tag '{tag.id}'")
    
    if tag.guidance_scale is not None and (tag.guidance_scale < 0 or tag.guidance_scale > 20):
        errors.append(f"Guidance scale {tag.guidance_scale} out of range [0, 20] for tag '{tag.id}'")
    
    if tag.strength is not None and (tag.strength < 0 or tag.strength > 1):
        errors.append(f"Strength {tag.strength} out of range [0, 1] for tag '{tag.id}'")
    
    return errors


def _is_valid_aspect_ratio(ratio: str) -> bool:
    """Check if aspect ratio is valid (e.g. 16:9, 4:3, 1:1)"""
    if not ratio:
        return False
    parts = ratio.split(':')
    if len(parts) != 2:
        return False
    try:
        w, h = int(parts[0]), int(parts[1])
        return w > 0 and h > 0
    except ValueError:
        return False


