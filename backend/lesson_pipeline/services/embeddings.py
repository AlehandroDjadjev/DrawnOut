"""
SigLIP2 embedding service for images and text.

Uses google/siglip2-giant-opt-patch16-384 via the vision app.
- 1.87B parameters
- 1536-dimensional embeddings
- Patch size: 16, Resolution: 384x384
- Trained on WebLI dataset
- Sigmoid loss for efficient scaling

All methods return Python-native List[float] for Pinecone compatibility.
"""
import logging
from typing import List, Tuple
from pathlib import Path
from urllib.parse import urlparse

from PIL import Image

from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Expected embedding dimension from config
EXPECTED_DIMENSION = config.embedding_dimension  # 1536

# Import from vision app
try:
    from vision.services.siglip2 import (
        encode_image_from_pil,
        encode_text as vision_encode_text,
        encode_images_from_pil_batch,
        encode_texts as vision_encode_texts,
    )
    VISION_APP_AVAILABLE = True
    logger.info("Vision app loaded successfully")
except ImportError as e:
    logger.warning(f"Vision app not available - embeddings will fail: {e}")
    VISION_APP_AVAILABLE = False


class EmbeddingDimensionError(ValueError):
    """Raised when embedding dimension doesn't match expected config."""
    pass


def _validate_dimension(embedding: List[float], source: str = "embedding") -> None:
    """
    Validate that embedding has the expected dimension.
    
    Args:
        embedding: The embedding vector to validate
        source: Description of where the embedding came from (for error message)
        
    Raises:
        EmbeddingDimensionError: If dimension doesn't match config.embedding_dimension
    """
    actual_dim = len(embedding)
    if actual_dim != EXPECTED_DIMENSION:
        raise EmbeddingDimensionError(
            f"{source} has dimension {actual_dim}, expected {EXPECTED_DIMENSION}. "
            f"Check SIGLIP_MODEL_NAME or EMBEDDING_DIMENSION config."
        )


def _tensor_to_list(tensor) -> List[float]:
    """
    Safely convert a torch tensor to a Python list of floats.
    
    Handles both 1D tensors and already-converted lists.
    """
    if hasattr(tensor, 'tolist'):
        return tensor.tolist()
    elif isinstance(tensor, list):
        return tensor
    else:
        raise TypeError(f"Expected tensor or list, got {type(tensor)}")


class SigLIPEmbeddingService:
    """Service for generating embeddings using SigLIP2 Giant OPT (via vision app)"""
    
    def __init__(self):
        if not VISION_APP_AVAILABLE:
            raise ImportError(
                "Vision app is not available. "
                "Make sure the 'vision' app is installed and configured correctly."
            )
    
    def embed_text(self, text: str) -> List[float]:
        """
        Generate embedding for text via vision app.
        
        Args:
            text: Input text
        
        Returns:
            List of floats (1536-dimensional embedding vector)
            
        Raises:
            EmbeddingDimensionError: If dimension doesn't match expected
        """
        try:
            embedding_tensor = vision_encode_text(text)
            embedding = _tensor_to_list(embedding_tensor)
            
            _validate_dimension(embedding, source=f"text embedding for '{text[:50]}...'")
            
            logger.debug(f"Generated text embedding: dimension={len(embedding)}")
            return embedding
            
        except EmbeddingDimensionError:
            raise
        except Exception as e:
            logger.error(f"Failed to embed text: {e}")
            raise
    
    def embed_image_from_pil(self, image: Image.Image) -> List[float]:
        """
        Generate embedding for a PIL image directly.
        
        Args:
            image: PIL Image object
        
        Returns:
            List of floats (1536-dimensional embedding vector)
            
        Raises:
            EmbeddingDimensionError: If dimension doesn't match expected
        """
        try:
            embedding_tensor = encode_image_from_pil(image)
            embedding = _tensor_to_list(embedding_tensor)
            
            _validate_dimension(embedding, source="PIL image embedding")
            
            logger.debug(f"Generated PIL image embedding: dimension={len(embedding)}")
            return embedding
            
        except EmbeddingDimensionError:
            raise
        except Exception as e:
            logger.error(f"Failed to embed PIL image: {e}")
            raise
    
    def embed_image(self, image_url: str) -> List[float]:
        """
        Generate embedding for image from URL or local path via vision app.
        
        Args:
            image_url: URL or local path of the image
        
        Returns:
            List of floats (1536-dimensional embedding vector)
            
        Raises:
            EmbeddingDimensionError: If dimension doesn't match expected
        """
        try:
            image = self._load_image_from_source(image_url)
            embedding = self.embed_image_from_pil(image)
            
            logger.debug(f"Generated image embedding: dimension={len(embedding)}")
            return embedding
            
        except EmbeddingDimensionError:
            raise
        except Exception as e:
            logger.error(f"Failed to embed image from {image_url}: {e}")
            raise
    
    def embed_image_batch(self, image_urls: List[str]) -> Tuple[List[List[float]], List[int]]:
        """
        Generate embeddings for multiple images via vision app.
        
        Args:
            image_urls: List of image URLs or local paths
        
        Returns:
            Tuple of (embeddings, success_indices)
            - embeddings: List of embedding vectors for successful images (List[List[float]])
            - success_indices: List of indices in original list that succeeded
        """
        embeddings: List[List[float]] = []
        success_indices: List[int] = []
        
        for i, url in enumerate(image_urls):
            try:
                embedding = self.embed_image(url)
                embeddings.append(embedding)
                success_indices.append(i)
            except Exception as e:
                logger.warning(f"Failed to embed image {url}: {e}")
                # Skip failed images - don't add zero vectors
        
        logger.info(
            f"Generated {len(embeddings)} image embeddings "
            f"({len(embeddings)}/{len(image_urls)} succeeded)"
        )
        return embeddings, success_indices
    
    def embed_images_from_pil_batch(
        self, 
        images: List[Image.Image]
    ) -> Tuple[List[List[float]], List[int]]:
        """
        Generate embeddings for multiple PIL images directly.
        
        More efficient than embed_image_batch when you already have PIL images,
        as it can batch the model forward pass.
        
        Args:
            images: List of PIL Image objects
        
        Returns:
            Tuple of (embeddings, success_indices)
            - embeddings: List of embedding vectors (List[List[float]])
            - success_indices: List of indices that succeeded
        """
        if not images:
            return [], []
        
        try:
            # Use vision batch helper for efficiency
            embeddings_tensor = encode_images_from_pil_batch(images)
            
            # Convert to list of lists
            embeddings = embeddings_tensor.tolist()
            
            # Validate dimension of first embedding
            if embeddings:
                _validate_dimension(embeddings[0], source="batch image embedding")
            
            success_indices = list(range(len(embeddings)))
            
            logger.info(f"Generated {len(embeddings)} image embeddings in batch")
            return embeddings, success_indices
            
        except Exception as e:
            logger.error(f"Batch image embedding failed: {e}")
            # Fall back to one-by-one processing
            logger.info("Falling back to sequential processing")
            embeddings = []
            success_indices = []
            for i, img in enumerate(images):
                try:
                    embedding = self.embed_image_from_pil(img)
                    embeddings.append(embedding)
                    success_indices.append(i)
                except Exception as inner_e:
                    logger.warning(f"Failed to embed image {i}: {inner_e}")
            
            return embeddings, success_indices
    
    def embed_texts_batch(self, texts: List[str]) -> List[List[float]]:
        """
        Generate embeddings for multiple text strings.
        
        Uses batch processing for efficiency.
        
        Args:
            texts: List of text strings
        
        Returns:
            List of embedding vectors (List[List[float]])
        """
        if not texts:
            return []
        
        try:
            # Use vision batch helper
            embeddings_tensor = vision_encode_texts(texts)
            embeddings = embeddings_tensor.tolist()
            
            # Validate dimension of first embedding
            if embeddings:
                _validate_dimension(embeddings[0], source="batch text embedding")
            
            logger.info(f"Generated {len(embeddings)} text embeddings in batch")
            return embeddings
            
        except Exception as e:
            logger.error(f"Batch text embedding failed: {e}")
            # Fall back to one-by-one
            embeddings = []
            for text in texts:
                try:
                    embedding = self.embed_text(text)
                    embeddings.append(embedding)
                except Exception as inner_e:
                    logger.warning(f"Failed to embed text '{text[:30]}...': {inner_e}")
                    # For text batch, we might want to maintain order
                    # Add zeros as placeholder (optional behavior)
            return embeddings

    def _load_image_from_source(self, image_url: str) -> Image.Image:
        """
        Load a PIL image either from a remote URL or a local file path.
        
        Args:
            image_url: HTTP(S) URL or local file path
            
        Returns:
            PIL Image in RGB mode
        """
        from io import BytesIO
        import requests

        normalized = (image_url or "").strip()
        parsed = urlparse(normalized)

        if parsed.scheme in ("http", "https"):
            headers = {
                'User-Agent': 'DrawnOutBot/1.0 (https://github.com/drawnout; educational@example.com) Python-Requests'
            }
            response = requests.get(
                normalized, 
                headers=headers, 
                timeout=config.embedding_timeout
            )
            response.raise_for_status()
            return Image.open(BytesIO(response.content)).convert('RGB')

        if parsed.scheme == "file":
            path = Path(parsed.path)
        else:
            path = Path(normalized)

        if not path.exists():
            raise FileNotFoundError(f"Image not found at path: {path}")

        return Image.open(path).convert('RGB')


# ============================================================================
# Global singleton instance
# ============================================================================
_embedding_service_instance = None


def get_embedding_service() -> SigLIPEmbeddingService:
    """Get or create the global embedding service instance"""
    global _embedding_service_instance
    if _embedding_service_instance is None:
        _embedding_service_instance = SigLIPEmbeddingService()
    return _embedding_service_instance


# ============================================================================
# Convenience functions (stable API for pipeline imports)
# ============================================================================

def embed_text(text: str) -> List[float]:
    """
    Generate text embedding.
    
    Returns:
        List[float] of length 1536
    """
    return get_embedding_service().embed_text(text)


def embed_image(image_url: str) -> List[float]:
    """
    Generate image embedding from URL or local path.
    
    Returns:
        List[float] of length 1536
    """
    return get_embedding_service().embed_image(image_url)


def embed_image_from_pil(image: Image.Image) -> List[float]:
    """
    Generate image embedding from PIL Image.
    
    Returns:
        List[float] of length 1536
    """
    return get_embedding_service().embed_image_from_pil(image)


def embed_images_batch(image_urls: List[str]) -> Tuple[List[List[float]], List[int]]:
    """
    Generate embeddings for multiple images.
    
    Returns:
        Tuple of (embeddings, success_indices)
        - embeddings: List[List[float]] where each inner list is length 1536
        - success_indices: List[int] of indices that succeeded
    """
    return get_embedding_service().embed_image_batch(image_urls)


def embed_images_from_pil_batch(
    images: List[Image.Image]
) -> Tuple[List[List[float]], List[int]]:
    """
    Generate embeddings for multiple PIL images.
    
    Returns:
        Tuple of (embeddings, success_indices)
    """
    return get_embedding_service().embed_images_from_pil_batch(images)


def embed_texts_batch(texts: List[str]) -> List[List[float]]:
    """
    Generate embeddings for multiple texts.
    
    Returns:
        List[List[float]] where each inner list is length 1536
    """
    return get_embedding_service().embed_texts_batch(texts)
