"""
SigLIP2 Feature Embedding Service

This module provides FEATURE EMBEDDINGS (not zero-shot classification) using SigLIP2.
Uses google/siglip2-giant-opt-patch16-384 by default:
- 1.87B parameters
- 1536-dimensional embeddings
- Patch size: 16, Resolution: 384x384
- Trained on WebLI dataset with sigmoid loss

All embeddings are L2-normalized for cosine similarity compatibility with Pinecone.
"""

import os
import logging
import threading
from typing import List, Tuple, Optional

import torch
from PIL import Image

logger = logging.getLogger(__name__)

# ============================================================================
# Module-level cache and thread lock for lazy singleton loading
# ============================================================================
_siglip_cache: Optional[Tuple] = None
_siglip_lock = threading.Lock()

# Default model - can be overridden via SIGLIP_MODEL_NAME env var
DEFAULT_MODEL_NAME = "google/siglip2-giant-opt-patch16-384"


def _get_device() -> Tuple[str, torch.dtype]:
    """
    Determine the device and dtype to use.
    
    Priority:
    1. VISION_DEVICE env var if set ("cpu" or "cuda")
    2. Auto-detect CUDA availability
    
    Returns:
        Tuple of (device_string, torch_dtype)
        - float16 on CUDA for memory efficiency
        - float32 on CPU for compatibility
    """
    env_device = os.environ.get("VISION_DEVICE", "").strip().lower()
    
    if env_device:
        device = env_device
    elif torch.cuda.is_available():
        device = "cuda"
    else:
        device = "cpu"
    
    dtype = torch.float16 if device == "cuda" else torch.float32
    
    logger.info(f"SigLIP2 using device: {device}, dtype: {dtype}")
    return device, dtype


def _get_siglip():
    """
    Lazy singleton loader for SigLIP2 model and processor.
    
    Thread-safe: uses a lock to prevent concurrent loading.
    Caches the model after first load.
    
    Returns:
        Tuple of (processor, model, device)
    """
    global _siglip_cache
    
    if _siglip_cache is not None:
        return _siglip_cache
    
    with _siglip_lock:
        # Double-check pattern - another thread may have loaded while we waited
        if _siglip_cache is not None:
            return _siglip_cache
        
        from transformers import AutoProcessor, AutoModel
        
        model_name = os.environ.get("SIGLIP_MODEL_NAME", DEFAULT_MODEL_NAME)
        device, dtype = _get_device()
        
        logger.info(f"Loading SigLIP2 model: {model_name}")
        
        # Load processor and model
        processor = AutoProcessor.from_pretrained(model_name)
        model = AutoModel.from_pretrained(
            model_name,
            torch_dtype=dtype,
        )
        
        # Move to device and set to eval mode
        model = model.to(device)
        model.eval()
        
        logger.info(f"SigLIP2 model loaded successfully on {device}")
        
        _siglip_cache = (processor, model, device)
        return _siglip_cache


def _normalize_l2(embeddings: torch.Tensor) -> torch.Tensor:
    """
    L2-normalize embeddings along the last dimension.
    
    This makes embeddings compatible with cosine similarity in Pinecone
    (dot product on normalized vectors = cosine similarity).
    
    Args:
        embeddings: Tensor of shape [..., dim]
        
    Returns:
        Normalized tensor with unit norm along last dimension
    """
    return embeddings / embeddings.norm(dim=-1, keepdim=True)


# ============================================================================
# Single-item encoding functions (stable API)
# ============================================================================

def encode_image_from_pil(image: Image.Image) -> torch.Tensor:
    """
    Generate a feature embedding for a PIL image.
    
    NOTE: This extracts FEATURE EMBEDDINGS using model.get_image_features(),
    NOT zero-shot classification logits.
    
    Args:
        image: PIL Image (will be converted to RGB if needed)
        
    Returns:
        torch.Tensor of shape [1536] - L2-normalized embedding on CPU
    """
    processor, model, device = _get_siglip()
    
    # Ensure RGB format
    if image.mode != "RGB":
        image = image.convert("RGB")
    
    # Process the image
    inputs = processor(images=image, return_tensors="pt")
    
    # Move inputs to device
    inputs = {k: v.to(device) for k, v in inputs.items()}
    
    # Generate embedding - using inference_mode for efficiency
    with torch.inference_mode():
        # FEATURE EMBEDDINGS - not zero-shot classification
        features = model.get_image_features(**inputs)
    
    # L2 normalize for cosine similarity
    features = _normalize_l2(features)
    
    # Return as 1D tensor on CPU
    return features[0].detach().cpu()


def encode_text(text: str) -> torch.Tensor:
    """
    Generate a feature embedding for a text string.
    
    NOTE: This extracts FEATURE EMBEDDINGS using model.get_text_features(),
    NOT zero-shot classification logits.
    
    Args:
        text: Input text string
        
    Returns:
        torch.Tensor of shape [1536] - L2-normalized embedding on CPU
    """
    processor, model, device = _get_siglip()
    
    # Process the text with proper padding/truncation
    inputs = processor(
        text=[text],
        padding="max_length",
        truncation=True,
        max_length=64,
        return_tensors="pt",
    )
    
    # Move inputs to device
    inputs = {k: v.to(device) for k, v in inputs.items()}
    
    # Generate embedding
    with torch.inference_mode():
        # FEATURE EMBEDDINGS - not zero-shot classification
        features = model.get_text_features(**inputs)
    
    # L2 normalize for cosine similarity
    features = _normalize_l2(features)
    
    # Return as 1D tensor on CPU
    return features[0].detach().cpu()


# ============================================================================
# Batch encoding functions (for ingestion performance)
# ============================================================================

def encode_images_from_pil_batch(images: List[Image.Image]) -> torch.Tensor:
    """
    Generate feature embeddings for a batch of PIL images.
    
    More efficient than calling encode_image_from_pil() in a loop
    as it batches the forward pass.
    
    Args:
        images: List of PIL Images (will be converted to RGB if needed)
        
    Returns:
        torch.Tensor of shape [N, 1536] - L2-normalized embeddings on CPU
    """
    if not images:
        return torch.empty(0, 1536)
    
    processor, model, device = _get_siglip()
    
    # Ensure all images are RGB
    rgb_images = []
    for img in images:
        if img.mode != "RGB":
            img = img.convert("RGB")
        rgb_images.append(img)
    
    # Process the batch
    inputs = processor(images=rgb_images, return_tensors="pt")
    
    # Move inputs to device
    inputs = {k: v.to(device) for k, v in inputs.items()}
    
    # Generate embeddings
    with torch.inference_mode():
        features = model.get_image_features(**inputs)
    
    # L2 normalize
    features = _normalize_l2(features)
    
    # Return on CPU
    return features.detach().cpu()


def encode_texts(texts: List[str]) -> torch.Tensor:
    """
    Generate feature embeddings for a batch of text strings.
    
    More efficient than calling encode_text() in a loop
    as it batches the forward pass.
    
    Args:
        texts: List of text strings
        
    Returns:
        torch.Tensor of shape [N, 1536] - L2-normalized embeddings on CPU
    """
    if not texts:
        return torch.empty(0, 1536)
    
    processor, model, device = _get_siglip()
    
    # Process the batch
    inputs = processor(
        text=texts,
        padding="max_length",
        truncation=True,
        max_length=64,
        return_tensors="pt",
    )
    
    # Move inputs to device
    inputs = {k: v.to(device) for k, v in inputs.items()}
    
    # Generate embeddings
    with torch.inference_mode():
        features = model.get_text_features(**inputs)
    
    # L2 normalize
    features = _normalize_l2(features)
    
    # Return on CPU
    return features.detach().cpu()

