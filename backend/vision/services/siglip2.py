# vision/services/siglip2.py
from functools import lru_cache
import logging

import torch
from transformers import pipeline, AutoModel, AutoProcessor
from transformers.image_utils import load_image

logger = logging.getLogger(__name__)

MODEL_ID = "google/siglip2-giant-opt-patch16-384"


def _choose_torch_dtype() -> torch.dtype:
    """
    Use bfloat16 if supported on the GPU, otherwise float16 on GPU, float32 on CPU.
    """
    if torch.cuda.is_available():
        is_bf16_supported = getattr(torch.cuda, "is_bf16_supported", lambda: False)()
        if is_bf16_supported:
            return torch.bfloat16
        return torch.float16
    return torch.float32


@lru_cache(maxsize=1)
def get_zero_shot_pipeline():
    """
    Lazily create and cache the zero-shot image classification pipeline.

    This uses device_map='auto' so that, if you have a GPU, Accelerate will
    place the model on GPU automatically; otherwise it will stay on CPU.
    """
    torch_dtype = _choose_torch_dtype()
    
    logger.info(f"🔄 Loading SigLIP2 zero-shot pipeline: {MODEL_ID}")
    logger.info(f"   torch_dtype={torch_dtype}, device=auto")

    pipe = pipeline(
        task="zero-shot-image-classification",
        model=MODEL_ID,
        device_map="auto",
        torch_dtype=torch_dtype,
    )

    # Make sure we're in eval mode
    if hasattr(pipe.model, "eval"):
        pipe.model.eval()

    logger.info(f"✅ SigLIP2 pipeline ready")
    return pipe


@lru_cache(maxsize=1)
def get_model_and_processor():
    """
    Get the raw SigLIP2 model and processor for embedding generation.
    Uses AutoModel + AutoProcessor so the correct Gemma tokenizer is used.
    """
    try:
        torch_dtype = _choose_torch_dtype()
        
        logger.info(f"🔄 Loading SigLIP2 model and processor: {MODEL_ID}")
        logger.info(f"   torch_dtype={torch_dtype}")
        
        logger.info(f"   Step 1: Loading model...")
        model = AutoModel.from_pretrained(
            MODEL_ID,
            device_map="auto",
            torch_dtype=torch_dtype,
        ).eval()
        logger.info(f"   ✓ Model loaded")
        
        logger.info(f"   Step 2: Loading processor...")
        processor = AutoProcessor.from_pretrained(MODEL_ID)
        logger.info(f"   ✓ Processor loaded")
        
        # Verify dimensions
        logger.info(f"   Step 3: Verifying dimensions...")
        test_input = processor(text=["test"], return_tensors="pt", padding=True)
        
        device = next(model.parameters()).device
        test_input = {k: v.to(device) for k, v in test_input.items()}
        
        with torch.no_grad():
            test_output = model.get_text_features(**test_input)
        
        actual_dim = test_output.shape[-1]
        logger.info(f"   ✅ Model ready! Embedding dimension: {actual_dim}")
        
        if actual_dim != 1536:
            logger.error(f"   ❌ WRONG DIMENSION! Expected 1536 but got {actual_dim}")
            raise RuntimeError(f"Model has wrong dimension: {actual_dim} != 1536")
        
        return model, processor
        
    except Exception as e:
        logger.error(f"❌ Failed to load SigLIP2 model: {e}")
        import traceback
        logger.error(traceback.format_exc())
        raise


def encode_image_from_pil(pil_image):
    """
    Returns a L2-normalized embedding vector as a 1D torch.Tensor on CPU.
    
    Args:
        pil_image: PIL Image object
    
    Returns:
        torch.Tensor: 1536-dimensional normalized embedding vector
    """
    model, processor = get_model_and_processor()
    inputs = processor(images=[pil_image], return_tensors="pt").to(model.device)

    with torch.no_grad():
        feats = model.get_image_features(**inputs)

    feats = torch.nn.functional.normalize(feats, dim=-1)
    return feats[0].cpu()


def encode_text(text: str):
    """
    Returns a L2-normalized text embedding vector as a 1D torch.Tensor on CPU.
    
    Args:
        text: Input text string
    
    Returns:
        torch.Tensor: 1536-dimensional normalized embedding vector
    """
    model, processor = get_model_and_processor()
    inputs = processor(text=[text], return_tensors="pt", padding=True).to(model.device)

    with torch.no_grad():
        feats = model.get_text_features(**inputs)

    feats = torch.nn.functional.normalize(feats, dim=-1)
    return feats[0].cpu()

