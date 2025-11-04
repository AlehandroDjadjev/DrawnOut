"""
Configuration for the lesson generation pipeline.
"""
import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class AppConfig:
    """Application configuration loaded from environment variables"""
    
    # Pinecone
    pinecone_api_key: str
    pinecone_environment: str
    pinecone_index_name: str = "lesson-images"
    
    # SigLIP / Embeddings
    siglip_model_name: str = "google/siglip2-giant-opt-patch16-384"
    embedding_dimension: int = 1536  # SigLIP2 Giant OPT embedding size
    
    # Image generation
    image_model_name: str = "sdxl"  # or whatever img2img model
    comfy_server_url: str = "http://127.0.0.1:8188"
    
    # Image research
    max_images_per_prompt: int = 40
    
    # Default image parameters
    default_aspect_ratio: str = "16:9"
    default_size: str = "1024x576"
    default_guidance_scale: float = 7.5
    default_strength: float = 0.7
    
    # API timeouts (seconds)
    image_research_timeout: int = 120
    embedding_timeout: int = 60
    pinecone_timeout: int = 30
    image_generation_timeout: int = 300
    
    # Retry configuration
    max_retries: int = 3
    retry_backoff_seconds: float = 2.0
    
    # Logging
    log_level: str = "INFO"


def load_config() -> AppConfig:
    """Load configuration from environment variables"""
    return AppConfig(
        # Pinecone (use existing env var names from lessons app)
        pinecone_api_key=os.getenv('Pinecone-API-Key', ''),
        pinecone_environment=os.getenv('PINECONE_ENVIRONMENT', 'us-east-1'),  # Just region, not cloud+region
        pinecone_index_name=os.getenv('PINECONE_INDEX_NAME', 'lesson-images'),
        
        # SigLIP
        siglip_model_name=os.getenv('SIGLIP_MODEL_NAME', 'google/siglip2-giant-opt-patch16-384'),
        embedding_dimension=int(os.getenv('EMBEDDING_DIMENSION', '1536')),
        
        # Image generation
        image_model_name=os.getenv('IMAGE_MODEL_NAME', 'sdxl'),
        comfy_server_url=os.getenv('COMFY_SERVER_URL', 'http://127.0.0.1:8188'),
        
        # Image research
        max_images_per_prompt=int(os.getenv('MAX_IMAGES_PER_PROMPT', '40')),
        
        # Defaults
        default_aspect_ratio=os.getenv('DEFAULT_ASPECT_RATIO', '16:9'),
        default_size=os.getenv('DEFAULT_SIZE', '1024x576'),
        default_guidance_scale=float(os.getenv('DEFAULT_GUIDANCE_SCALE', '7.5')),
        default_strength=float(os.getenv('DEFAULT_STRENGTH', '0.7')),
        
        # Timeouts
        image_research_timeout=int(os.getenv('IMAGE_RESEARCH_TIMEOUT', '120')),
        embedding_timeout=int(os.getenv('EMBEDDING_TIMEOUT', '60')),
        pinecone_timeout=int(os.getenv('PINECONE_TIMEOUT', '30')),
        image_generation_timeout=int(os.getenv('IMAGE_GENERATION_TIMEOUT', '300')),
        
        # Retry
        max_retries=int(os.getenv('MAX_RETRIES', '3')),
        retry_backoff_seconds=float(os.getenv('RETRY_BACKOFF_SECONDS', '2.0')),
        
        # Logging
        log_level=os.getenv('LOG_LEVEL', 'INFO'),
    )


# Global config instance
config = load_config()

