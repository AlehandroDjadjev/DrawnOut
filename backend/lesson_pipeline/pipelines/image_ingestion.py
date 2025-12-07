"""
Image research and indexing pipeline.

Researches images, generates embeddings, and stores in Pinecone.
"""
import logging
from typing import List, Dict
import uuid

from lesson_pipeline.types import UserPrompt, ImageCandidate, ImageEmbeddingRecord
from lesson_pipeline.services.image_researcher import research_images
from lesson_pipeline.services.embeddings import embed_images_batch
from lesson_pipeline.services.vector_store import upsert_images
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)


async def run_image_research_and_index(
    prompt: UserPrompt,
    subject: str = "General",
    max_images: int = None
) -> Dict[str, any]:
    """
    Research images and index them in Pinecone.
    
    Args:
        prompt: User prompt
        subject: Subject area
        max_images: Max number of images
    
    Returns:
        {
            "topic_id": str,
            "indexed_count": int,
            "candidates": List[ImageCandidate]
        }
    """
    topic_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, prompt.text))
    max_imgs = max_images or config.max_images_per_prompt
    
    logger.info(f"Starting image research for topic_id={topic_id}")
    
    try:
        # 1. Research images
        logger.info(f"Researching images: query='{prompt.text}', subject='{subject}'")
        candidates = research_images(
            query=prompt.text,
            subject=subject,
            max_images=max_imgs
        )
        
        if not candidates:
            logger.warning("No images found")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": []
            }
        
        logger.info(f"Found {len(candidates)} candidate images")
        
        # 2. Generate embeddings (batch)
        logger.info("Generating embeddings for images")
        image_urls = [c.source_url for c in candidates]
        vectors, success_indices = embed_images_batch(image_urls)
        
        # 3. Create embedding records (only for successfully embedded images)
        records: List[ImageEmbeddingRecord] = []
        for i, vec_idx in enumerate(success_indices):
            candidate = candidates[vec_idx]
            
            metadata = {
                'title': candidate.title,
                'description': candidate.description,
                'source': candidate.source,
                'tags': candidate.tags,
                'license': candidate.license,
                'width': candidate.width,
                'height': candidate.height,
                'subject': subject,
                'query': prompt.text,
            }
            if candidate.metadata:
                metadata.update(candidate.metadata)

            record = ImageEmbeddingRecord(
                id=candidate.id,
                image_url=candidate.source_url,
                vector=vectors[i],
                topic_id=topic_id,
                original_prompt=prompt.text,
                metadata=metadata
            )
            records.append(record)
        
        # 4. Upsert to Pinecone
        logger.info(f"Upserting {len(records)} records to Pinecone")
        upsert_images(records)
        
        logger.info(f"Successfully indexed {len(records)} images for topic {topic_id}")
        
        return {
            "topic_id": topic_id,
            "indexed_count": len(records),
            "candidates": candidates
        }
        
    except Exception as e:
        logger.error(f"Image research and indexing failed: {e}")
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": []
        }


# Sync version for now (async can be added later)
def run_image_research_and_index_sync(
    prompt: UserPrompt,
    subject: str = "General",
    max_images: int = None
) -> Dict[str, any]:
    """Synchronous version of image research and indexing"""
    topic_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, prompt.text))
    max_imgs = max_images or config.max_images_per_prompt
    
    logger.info(f"Starting image research for topic_id={topic_id}")
    
    try:
        # 1. Research images
        logger.info(f"Researching images: query='{prompt.text}', subject='{subject}'")
        candidates = research_images(
            query=prompt.text,
            subject=subject,
            max_images=max_imgs
        )
        
        if not candidates:
            logger.warning("No images found")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": []
            }
        
        logger.info(f"Found {len(candidates)} candidate images")
        
        # 2. Generate embeddings (batch)
        logger.info("Generating embeddings for images")
        image_urls = [c.source_url for c in candidates]
        vectors, success_indices = embed_images_batch(image_urls)
        
        # 3. Create embedding records (only for successfully embedded images)
        records: List[ImageEmbeddingRecord] = []
        for i, vec_idx in enumerate(success_indices):
            candidate = candidates[vec_idx]
            
            metadata = {
                'title': candidate.title,
                'description': candidate.description,
                'source': candidate.source,
                'tags': candidate.tags,
                'license': candidate.license,
                'width': candidate.width,
                'height': candidate.height,
                'subject': subject,
                'query': prompt.text,
            }
            if candidate.metadata:
                metadata.update(candidate.metadata)

            record = ImageEmbeddingRecord(
                id=candidate.id,
                image_url=candidate.source_url,
                vector=vectors[i],
                topic_id=topic_id,
                original_prompt=prompt.text,
                metadata=metadata
            )
            records.append(record)
        
        # 4. Upsert to Pinecone
        logger.info(f"Upserting {len(records)} records to Pinecone")
        upsert_images(records)
        
        logger.info(f"Successfully indexed {len(records)} images for topic {topic_id}")
        
        return {
            "topic_id": topic_id,
            "indexed_count": len(records),
            "candidates": candidates
        }
        
    except Exception as e:
        logger.error(f"Image research and indexing failed: {e}")
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": []
        }

