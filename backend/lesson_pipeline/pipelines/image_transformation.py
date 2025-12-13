"""
Image transformation pipeline.

Transforms base images using image-to-image models.
"""
import logging
from typing import List, Dict

from lesson_pipeline.types import ResolvedImage
from lesson_pipeline.services.image_to_image import transform_image, get_image_to_image_service

logger = logging.getLogger(__name__)


def transform_resolved_images(resolved_base: List[Dict]) -> List[ResolvedImage]:
    """
    Transform base images using img2img.
    
    Args:
        resolved_base: List of dicts with tag, base_image_url, base_metadata
    
    Returns:
        List of ResolvedImage with final transformed images
    """
    logger.info(f"Transforming {len(resolved_base)} images")
    
    # Check if ComfyUI is available
    service = get_image_to_image_service()
    comfy_available = service.is_available()
    
    if not comfy_available:
        logger.warning("⚠️ ComfyUI is not available (port 8188 not responding). Using base images without transformation.")
        logger.info("   To enable image transformation, start ComfyUI on http://127.0.0.1:8188")
        
        # Return base images directly without attempting transformation
        results: List[ResolvedImage] = []
        for item in resolved_base:
            tag = item['tag']
            base_image_url = item['base_image_url']
            vector_id = item.get('vector_id')
            
            resolved = ResolvedImage(
                tag=tag,
                base_image_url=base_image_url,
                final_image_url=base_image_url or "",
                vector_id=vector_id,
                metadata={
                    'base': item.get('base_metadata'),
                    'comfy_available': False,
                    'transformation_skipped': True,
                }
            )
            results.append(resolved)
        
        return results
    
    logger.info("✅ ComfyUI is available - transforming images")
    
    results: List[ResolvedImage] = []
    
    for item in resolved_base:
        tag = item['tag']
        base_image_url = item['base_image_url']
        vector_id = item.get('vector_id')
        
        try:
            # Determine if we should use base image or generate from scratch
            use_base = bool(base_image_url)
            
            if use_base:
                logger.debug(f"Transforming base image for tag {tag.id}")
                final_url = transform_image(
                    base_image_url=base_image_url,
                    prompt=tag.prompt,
                    style=tag.style,
                    aspect_ratio=tag.aspect_ratio,
                    size=tag.size,
                    guidance_scale=tag.guidance_scale,
                    strength=tag.strength
                )
            else:
                # No base image - use text-to-image (same API, just no base)
                logger.debug(f"Generating image from scratch for tag {tag.id}")
                final_url = transform_image(
                    base_image_url="",  # Empty means text-to-image
                    prompt=tag.prompt,
                    style=tag.style,
                    aspect_ratio=tag.aspect_ratio,
                    size=tag.size,
                    guidance_scale=tag.guidance_scale,
                    strength=0.0  # Not applicable for text-to-image
                )
            
            resolved = ResolvedImage(
                tag=tag,
                base_image_url=base_image_url,
                final_image_url=final_url,
                vector_id=vector_id,
                metadata={
                    'base': item.get('base_metadata'),
                    'transformation_used': use_base,
                }
            )
            
            results.append(resolved)
            
            logger.info(f"Transformed tag {tag.id}: {final_url[:50]}...")
            
        except Exception as e:
            logger.error(f"Failed to transform image for tag {tag.id}: {e}")
            # Use base image as fallback
            resolved = ResolvedImage(
                tag=tag,
                base_image_url=base_image_url,
                final_image_url=base_image_url or "",
                vector_id=vector_id,
                metadata={
                    'base': item.get('base_metadata'),
                    'error': str(e),
                }
            )
            results.append(resolved)
    
    logger.info(f"Successfully transformed {len(results)} images")
    
    return results

