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

import requests
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
        Automatically converts SVG/GIF to PNG before embedding.
        SVGs that can't be converted are skipped gracefully.
        
        Args:
            image_urls: List of image URLs or local paths
        
        Returns:
            Tuple of (embeddings, success_indices)
            - embeddings: List of embedding vectors for successful images (List[List[float]])
            - success_indices: List of indices in original list that succeeded
        """
        embeddings: List[List[float]] = []
        success_indices: List[int] = []
        converted_count = 0
        skipped_svg_count = 0
        
        for i, url in enumerate(image_urls):
            url_lower = (url or "").lower()
            is_svg = '.svg' in url_lower
            is_gif = '.gif' in url_lower
            
            try:
                embedding = self.embed_image(url)
                embeddings.append(embedding)
                success_indices.append(i)
                if is_svg or is_gif:
                    converted_count += 1
            except ValueError as e:
                # SVG conversion failed - skip gracefully
                if is_svg and "SVG conversion failed" in str(e):
                    logger.info(f"Skipping SVG (no converter available): {url[:60]}...")
                    skipped_svg_count += 1
                else:
                    logger.warning(f"Failed to embed image {url}: {e}")
            except Exception as e:
                logger.warning(f"Failed to embed image {url}: {e}")
                # Skip failed images - don't add zero vectors
        
        msg = f"Generated {len(embeddings)} image embeddings ({len(embeddings)}/{len(image_urls)} succeeded"
        if converted_count > 0:
            msg += f", {converted_count} converted from SVG/GIF"
        if skipped_svg_count > 0:
            msg += f", {skipped_svg_count} SVGs skipped (install Cairo or ImageMagick to convert)"
        msg += ")"
        logger.info(msg)
        
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

    def _convert_wikimedia_svg_to_png_url(self, svg_url: str, width: int = 512) -> str:
        """
        Convert a Wikimedia SVG URL to a PNG thumbnail URL.
        
        Wikimedia Commons provides automatic PNG rendering of SVGs via their thumbnail API.
        Example:
            Input:  https://upload.wikimedia.org/wikipedia/commons/f/f6/Example.svg
            Output: https://upload.wikimedia.org/wikipedia/commons/thumb/f/f6/Example.svg/512px-Example.svg.png
        
        Args:
            svg_url: Original Wikimedia SVG URL
            width: Desired width in pixels (default 512)
            
        Returns:
            PNG thumbnail URL, or original URL if conversion not possible
        """
        import re
        
        # Pattern: https://upload.wikimedia.org/wikipedia/commons/X/XX/Filename.svg
        # Becomes: https://upload.wikimedia.org/wikipedia/commons/thumb/X/XX/Filename.svg/WIDTHpx-Filename.svg.png
        pattern = r'(https://upload\.wikimedia\.org/wikipedia/commons/)([a-f0-9]/[a-f0-9]{2}/)([^/]+\.svg)$'
        match = re.match(pattern, svg_url, re.IGNORECASE)
        
        if match:
            base = match.group(1)
            path = match.group(2)
            filename = match.group(3)
            png_url = f"{base}thumb/{path}{filename}/{width}px-{filename}.png"
            logger.info(f"Converted Wikimedia SVG to PNG thumbnail URL")
            return png_url
        
        # If not a standard Wikimedia URL, return original
        return svg_url
    
    def _convert_svg_to_png(self, svg_data: bytes) -> bytes:
        """
        Convert SVG data to PNG. Tries multiple backends in order:
        1. cairosvg (if Cairo library is installed) - best quality
        2. Wand/ImageMagick (if ImageMagick is installed)
        3. svglib + reportlab (needs Cairo for renderPM)
        
        Args:
            svg_data: Raw SVG file bytes
            
        Returns:
            PNG image bytes
            
        Raises:
            ValueError: If conversion is not possible with any backend
        """
        from io import BytesIO
        
        errors = []
        
        # Try cairosvg first (best quality)
        try:
            import cairosvg
            png_data = cairosvg.svg2png(bytestring=svg_data, output_width=512)
            logger.debug("Converted SVG to PNG using cairosvg")
            return png_data
        except ImportError:
            errors.append("cairosvg not installed")
        except OSError as e:
            errors.append(f"Cairo library not found")
        except Exception as e:
            errors.append(f"cairosvg error: {e}")
        
        # Try Wand/ImageMagick
        try:
            from wand.image import Image as WandImage
            with WandImage(blob=svg_data, format='svg') as img:
                img.format = 'png'
                img.resize(512, int(512 * img.height / img.width) if img.width > 0 else 512)
                png_data = img.make_blob()
            logger.debug("Converted SVG to PNG using Wand/ImageMagick")
            return png_data
        except ImportError:
            errors.append("Wand not installed")
        except Exception as e:
            errors.append(f"Wand/ImageMagick error: {e}")
        
        # Try svglib + reportlab (also needs Cairo for renderPM)
        try:
            from svglib.svglib import svg2rlg
            from reportlab.graphics import renderPM
            
            svg_io = BytesIO(svg_data)
            drawing = svg2rlg(svg_io)
            
            if drawing is None:
                raise ValueError("svglib could not parse SVG")
            
            scale = 512.0 / drawing.width if drawing.width > 0 else 1.0
            drawing.width = 512
            drawing.height = drawing.height * scale
            drawing.scale(scale, scale)
            
            png_io = BytesIO()
            renderPM.drawToFile(drawing, png_io, fmt='PNG')
            png_io.seek(0)
            logger.debug("Converted SVG to PNG using svglib")
            return png_io.read()
        except ImportError:
            errors.append("svglib/reportlab not installed")
        except Exception as e:
            errors.append(f"svglib error: {e}")
        
        # No conversion method available
        raise ValueError(
            f"SVG conversion failed. Errors: {'; '.join(errors)}. "
            "Install Cairo library (Windows: https://github.com/nickveld/win-gtk3) "
            "or ImageMagick (https://imagemagick.org/script/download.php)"
        )
    
    def _fetch_with_retry(self, url: str, headers: dict, max_retries: int = 2) -> requests.Response:
        """
        Fetch URL with minimal retries. Fail fast on permanent errors (403, 404, etc.)
        to skip failed embeds quickly instead of blocking on slow/broken URLs.

        Uses short timeout (embedding_fetch_timeout) so bad URLs don't block the batch.
        """
        import time

        fetch_timeout = getattr(config, 'embedding_fetch_timeout', 15) or 15

        for attempt in range(max_retries):
            if attempt > 0:
                time.sleep(1)  # Brief backoff only for retryable errors

            try:
                response = requests.get(url, headers=headers, timeout=fetch_timeout)
            except (requests.Timeout, requests.ConnectionError) as e:
                logger.warning(f"Fetch failed (attempt {attempt + 1}): {e}")
                if attempt == max_retries - 1:
                    raise
                continue

            # Fail fast - no retries for permanent errors
            if response.status_code in (403, 404, 410, 451):
                logger.debug(f"Permanent error {response.status_code} for {url[:50]}..., skipping")
                response.raise_for_status()

            if response.status_code == 429:
                if attempt < max_retries - 1:
                    logger.warning(f"Rate limited (429), retrying...")
                    continue
                response.raise_for_status()

            response.raise_for_status()
            return response

        # Should not reach here; fail safely
        raise requests.HTTPError("Max retries exceeded")
    
    def _load_image_from_source(self, image_url: str) -> Image.Image:
        """
        Load a PIL image either from a remote URL or a local file path.
        Automatically converts SVG files to PNG for embedding:
        - Wikimedia SVGs: Uses Wikimedia's thumbnail API (no dependencies needed)
        - Other SVGs: Uses cairosvg if available
        Standardizes all images to PNG-compatible RGB format.
        
        Args:
            image_url: HTTP(S) URL or local file path
            
        Returns:
            PIL Image in RGB mode
        """
        from io import BytesIO

        normalized = (image_url or "").strip()
        parsed = urlparse(normalized)
        is_svg = normalized.lower().endswith('.svg') or 'image/svg' in normalized.lower()
        is_wikimedia = 'upload.wikimedia.org' in normalized.lower()
        is_wikimedia_svg = is_svg and is_wikimedia

        if parsed.scheme in ("http", "https"):
            # Wikimedia requires a proper User-Agent with contact info per their policy
            # https://meta.wikimedia.org/wiki/User-Agent_policy
            headers = {
                'User-Agent': 'DrawnOutBot/1.0 (https://drawnout.app; mailto:api@drawnout.app) python-requests/2.32',
                'Accept': 'image/png,image/jpeg,image/gif,image/webp,image/svg+xml,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9',
                'Accept-Encoding': 'gzip, deflate',
            }
            
            # For Wikimedia SVGs, convert URL to PNG thumbnail URL
            if is_wikimedia_svg:
                png_url = self._convert_wikimedia_svg_to_png_url(normalized)
                if png_url != normalized:
                    # Successfully converted - fetch the PNG thumbnail instead
                    try:
                        response = self._fetch_with_retry(png_url, headers)
                        return Image.open(BytesIO(response.content)).convert('RGB')
                    except requests.HTTPError as e:
                        logger.warning(f"Wikimedia PNG thumbnail failed: {e}, trying original SVG")
                        # Fall through to try original SVG with cairosvg
            
            response = self._fetch_with_retry(normalized, headers)
            
            content = response.content
            content_type = response.headers.get('Content-Type', '').lower()
            
            # Check if response is SVG (by URL extension or content type)
            if is_svg or 'svg' in content_type:
                logger.info(f"Converting SVG to PNG: {normalized[:60]}...")
                try:
                    png_data = self._convert_svg_to_png(content)
                    return Image.open(BytesIO(png_data)).convert('RGB')
                except ValueError as e:
                    # cairosvg not available
                    logger.warning(f"Cannot convert SVG: {e}")
                    raise
            
            # For GIF, take first frame and convert to RGB
            if normalized.lower().endswith('.gif') or 'gif' in content_type:
                img = Image.open(BytesIO(content))
                # Get first frame of GIF
                img.seek(0)
                return img.convert('RGB')
            
            return Image.open(BytesIO(content)).convert('RGB')

        # Local file handling
        if parsed.scheme == "file":
            path = Path(parsed.path)
        else:
            path = Path(normalized)

        if not path.exists():
            raise FileNotFoundError(f"Image not found at path: {path}")

        # Handle local SVG files
        if str(path).lower().endswith('.svg'):
            logger.info(f"Converting local SVG to PNG: {path}")
            with open(path, 'rb') as f:
                svg_data = f.read()
            png_data = self._convert_svg_to_png(svg_data)
            return Image.open(BytesIO(png_data)).convert('RGB')
        
        # Handle local GIF files
        if str(path).lower().endswith('.gif'):
            img = Image.open(path)
            img.seek(0)
            return img.convert('RGB')

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
