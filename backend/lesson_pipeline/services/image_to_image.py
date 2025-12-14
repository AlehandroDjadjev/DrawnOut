"""
Image-to-image transformation service using ComfyUI (via imggen app).
"""
import logging
import requests
from typing import Optional, Dict, Any
from pathlib import Path

from lesson_pipeline.config import config

logger = logging.getLogger(__name__)


class Image2ImageService:
    """Service for transforming images using ComfyUI"""
    
    def __init__(self):
        self.comfy_url = config.comfy_server_url
        self.timeout = config.image_generation_timeout
    
    def transform_image(
        self,
        base_image_url: str,
        prompt: str,
        style: Optional[str] = None,
        aspect_ratio: Optional[str] = None,
        size: Optional[str] = None,
        guidance_scale: Optional[float] = None,
        strength: Optional[float] = None
    ) -> str:
        """
        Transform an image using ComfyUI.
        
        Args:
            base_image_url: URL of base image
            prompt: Transformation prompt
            style: Style descriptor (e.g., "scientific diagram", "photo")
            aspect_ratio: Aspect ratio (e.g., "16:9")
            size: Size (e.g., "1024x576")
            guidance_scale: Guidance scale for generation
            strength: Strength of transformation (0-1)
        
        Returns:
            URL or path to final image
        """
        try:
            # Build full prompt with style
            full_prompt = prompt
            if style:
                full_prompt = f"{prompt}, {style} style"
            
            # Use wb_generate API endpoint (wraps whiteboard imggen)
            imggen_url = "http://localhost:8000/api/wb/generate/generate/"
            
            payload = {
                "prompts": [full_prompt],
                "seed": 42,  # Fixed seed for consistency
                "steps": 20,
                "cfg": guidance_scale or config.default_guidance_scale,
            }
            
            # Add size if specified
            if size:
                payload["path_out"] = "lesson_pipeline_outputs"
            
            logger.debug(f"Calling imggen with prompt: {full_prompt}")
            
            response = requests.post(
                imggen_url,
                json=payload,
                timeout=self.timeout
            )
            response.raise_for_status()
            
            result = response.json()
            
            if result.get('ok') and result.get('results'):
                first_result = result['results'][0]
                if 'saved' in first_result and first_result['saved']:
                    final_path = first_result['saved'][0]
                    logger.info(f"Generated image: {final_path}")
                    return final_path
                elif 'error' in first_result:
                    logger.error(f"Image generation error: {first_result['error']}")
            
            # Fallback: return base image if generation failed
            logger.warning("Image generation failed, using base image")
            return base_image_url
            
        except Exception as e:
            logger.error(f"Failed to transform image: {e}")
            # Return base image as fallback
            return base_image_url
    
    def is_available(self) -> bool:
        """Check if ComfyUI is available"""
        try:
            response = requests.get(
                f"{self.comfy_url}/system_stats",
                timeout=5
            )
            return response.status_code == 200
        except Exception:
            return False


# Global singleton
_image_to_image_service: Optional[Image2ImageService] = None


def get_image_to_image_service() -> Image2ImageService:
    """Get or create the global image-to-image service"""
    global _image_to_image_service
    if _image_to_image_service is None:
        _image_to_image_service = Image2ImageService()
    return _image_to_image_service


# Convenience function
def transform_image(
    base_image_url: str,
    prompt: str,
    **kwargs
) -> str:
    """Transform an image"""
    return get_image_to_image_service().transform_image(
        base_image_url,
        prompt,
        **kwargs
    )









