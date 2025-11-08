"""
SigLIP2 embedding service for images and text.

Uses google/siglip2-giant-opt-patch16-384 via the vision app.
- 1.87B parameters
- 1536-dimensional embeddings
- Patch size: 16, Resolution: 384x384
- Trained on WebLI dataset
- Sigmoid loss for efficient scaling
"""
import logging
from typing import List
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

# Import from vision app
try:
    from vision.services.siglip2 import encode_image_from_pil, encode_text as vision_encode_text
    VISION_APP_AVAILABLE = True
except ImportError:
    logger.warning("Vision app not available - embeddings will fail")
    VISION_APP_AVAILABLE = False


class SigLIPEmbeddingService:
    """Service for generating embeddings using SigLIP2 Giant OPT (via vision app)"""
    
    def __init__(self):
        if not VISION_APP_AVAILABLE:
            raise ImportError("Vision app is not available. Make sure it's installed and configured.")
    
    def embed_text(self, text: str) -> List[float]:
        """
        Generate embedding for text via vision app.
        
        Args:
            text: Input text
        
        Returns:
            List of floats (1536-dimensional embedding vector)
        """
        try:
            embedding_tensor = vision_encode_text(text)
            embedding = embedding_tensor.tolist()
            logger.debug(f"Generated text embedding: dimension={len(embedding)}")
            return embedding
        except Exception as e:
            logger.error(f"Failed to embed text: {e}")
            raise
    
    def embed_image(self, image_url: str) -> List[float]:
        """
        Generate embedding for image from URL via vision app.
        
        Args:
            image_url: URL of the image
        
        Returns:
            List of floats (1536-dimensional embedding vector)
        """
        try:
            import requests
            from PIL import Image
            from io import BytesIO
            from lesson_pipeline.config import config
            
            # Download image with proper headers for Wikimedia
            headers = {
                'User-Agent': 'DrawnOutBot/1.0 (https://github.com/drawnout; educational@example.com) Python-Requests'
            }
            response = requests.get(image_url, headers=headers, timeout=config.embedding_timeout)
            response.raise_for_status()
            
            # Open image
            image = Image.open(BytesIO(response.content)).convert('RGB')
            
            # Generate embedding via vision app
            embedding_tensor = encode_image_from_pil(image)
            embedding = embedding_tensor.tolist()
            
            logger.debug(f"Generated image embedding: dimension={len(embedding)}")
            return embedding
            
        except Exception as e:
            logger.error(f"Failed to embed image from {image_url}: {e}")
            raise
    
    def embed_image_batch(self, image_urls: List[str]) -> tuple[List[List[float]], List[int]]:
        """
        Generate embeddings for multiple images via vision app.
        
        Args:
            image_urls: List of image URLs
        
        Returns:
            Tuple of (embeddings, success_indices)
            - embeddings: List of embedding vectors for successful images
            - success_indices: List of indices in original list that succeeded
        """
        embeddings = []
        success_indices = []
        
        for i, url in enumerate(image_urls):
            try:
                embedding = self.embed_image(url)
                embeddings.append(embedding)
                success_indices.append(i)
            except Exception as e:
                logger.warning(f"Failed to embed image {url}: {e}")
                # Skip failed images - don't add zero vectors
        
        logger.info(f"Generated {len(embeddings)} image embeddings ({len(embeddings)}/{len(image_urls)} succeeded)")
        return embeddings, success_indices


# Global singleton instance
_embedding_service_instance = None

def get_embedding_service() -> SigLIPEmbeddingService:
    """Get or create the global embedding service instance"""
    global _embedding_service_instance
    if _embedding_service_instance is None:
        _embedding_service_instance = SigLIPEmbeddingService()
    return _embedding_service_instance


# Convenience functions
def embed_text(text: str) -> List[float]:
    """Generate text embedding"""
    return get_embedding_service().embed_text(text)


def embed_image(image_url: str) -> List[float]:
    """Generate image embedding"""
    return get_embedding_service().embed_image(image_url)


def embed_images_batch(image_urls: List[str]) -> tuple[List[List[float]], List[int]]:
    """Generate embeddings for multiple images. Returns (embeddings, success_indices)"""
    return get_embedding_service().embed_image_batch(image_urls)

