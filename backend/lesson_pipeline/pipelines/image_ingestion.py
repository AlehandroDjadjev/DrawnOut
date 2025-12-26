"""
Image research and indexing pipeline.

Researches images, generates embeddings, and stores in Pinecone.

Pipeline flow:
1. Research images via ImageResearchService → List[ImageCandidate]
2. Download/process images → PIL Images
3. Generate embeddings via SigLIPEmbeddingService → List[List[float]]
4. Create ImageEmbeddingRecord with metadata
5. Upsert to Pinecone via PineconeVectorStore
"""
import logging
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
import uuid

from lesson_pipeline.types import UserPrompt, ImageCandidate, ImageEmbeddingRecord
from lesson_pipeline.services.image_researcher import research_images
from lesson_pipeline.services.embeddings import embed_images_batch
from lesson_pipeline.services.vector_store import upsert_images
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)


@dataclass
class IngestionStats:
    """Statistics from the image ingestion pipeline."""
    topic_id: str
    candidates_found: int = 0
    embedding_attempts: int = 0
    embedding_successes: int = 0
    embedding_failures: int = 0
    records_created: int = 0
    upserted_count: int = 0
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "topic_id": self.topic_id,
            "candidates_found": self.candidates_found,
            "embedding_attempts": self.embedding_attempts,
            "embedding_successes": self.embedding_successes,
            "embedding_failures": self.embedding_failures,
            "records_created": self.records_created,
            "upserted_count": self.upserted_count,
            "errors": self.errors,
        }


def _generate_topic_id(prompt_text: str) -> str:
    """Generate a deterministic topic ID from prompt text."""
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, prompt_text))


def _build_metadata(
    candidate: ImageCandidate,
    subject: str,
    prompt_text: str
) -> Dict[str, Any]:
    """
    Build metadata dict for an ImageEmbeddingRecord.
    
    Filters out None values to avoid Pinecone rejection.
    """
    metadata = {
        'title': candidate.title,
        'description': candidate.description,
        'source': candidate.source,
        'tags': candidate.tags,
        'license': candidate.license,
        'width': candidate.width,
        'height': candidate.height,
        'subject': subject,
        'query': prompt_text,
    }
    
    # Merge candidate's extra metadata
    if candidate.metadata:
        metadata.update(candidate.metadata)
    
    # Filter out None values (Pinecone rejects them)
    return {k: v for k, v in metadata.items() if v is not None}


def _create_embedding_records(
    candidates: List[ImageCandidate],
    vectors: List[List[float]],
    success_indices: List[int],
    topic_id: str,
    prompt_text: str,
    subject: str,
) -> List[ImageEmbeddingRecord]:
    """
    Create ImageEmbeddingRecord objects for successfully embedded images.
    
    Args:
        candidates: Original list of image candidates
        vectors: Successfully generated embedding vectors
        success_indices: Indices in original candidates list that succeeded
        topic_id: Topic identifier
        prompt_text: Original prompt text
        subject: Subject area
        
    Returns:
        List of ImageEmbeddingRecord ready for Pinecone upsert
    """
    records: List[ImageEmbeddingRecord] = []
    
    for vector_idx, candidate_idx in enumerate(success_indices):
        candidate = candidates[candidate_idx]
        
        record = ImageEmbeddingRecord(
            id=candidate.id,
            image_url=candidate.source_url,
            vector=vectors[vector_idx],
            topic_id=topic_id,
            original_prompt=prompt_text,
            metadata=_build_metadata(candidate, subject, prompt_text)
        )
        records.append(record)
    
    return records


async def run_image_research_and_index(
    prompt: UserPrompt,
    subject: str = "General",
    max_images: Optional[int] = None
) -> Dict[str, Any]:
    """
    Research images and index them in Pinecone (async version).
    
    Pipeline:
    1. Research images → candidates
    2. Embed images (downloads handled by embed_images_batch)
    3. Create records with metadata
    4. Upsert to Pinecone
    
    Args:
        prompt: User prompt containing the search query
        subject: Subject area (e.g., "Biology", "Physics")
        max_images: Maximum number of images to process
    
    Returns:
        Dict with keys:
            - topic_id: str
            - indexed_count: int
            - candidates: List[ImageCandidate]
            - stats: IngestionStats dict
    """
    topic_id = _generate_topic_id(prompt.text)
    max_imgs = max_images or config.max_images_per_prompt
    stats = IngestionStats(topic_id=topic_id)
    
    logger.info(f"[Ingestion] Starting for topic_id={topic_id}, query='{prompt.text[:50]}...'")
    
    # -------------------------------------------------------------------------
    # Step 1: Research images
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 1: Researching images (subject={subject}, limit={max_imgs})")
        candidates = research_images(
            query=prompt.text,
            subject=subject,
            max_images=max_imgs
        )
        stats.candidates_found = len(candidates)
        
        if not candidates:
            logger.warning(f"[Ingestion] No images found for query: '{prompt.text}'")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": [],
                "stats": stats.to_dict()
            }
        
        logger.info(f"[Ingestion] Found {len(candidates)} candidate images")
        
    except Exception as e:
        error_msg = f"Research phase failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": [],
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 2: Generate embeddings (includes download)
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 2: Generating embeddings for {len(candidates)} images")
        stats.embedding_attempts = len(candidates)
        
        image_urls = [c.source_url for c in candidates]
        vectors, success_indices = embed_images_batch(image_urls)
        
        stats.embedding_successes = len(success_indices)
        stats.embedding_failures = len(candidates) - len(success_indices)
        
        logger.info(
            f"[Ingestion] Embeddings: {stats.embedding_successes}/{stats.embedding_attempts} succeeded, "
            f"{stats.embedding_failures} failed"
        )
        
        if not vectors:
            logger.warning("[Ingestion] No embeddings generated successfully")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": candidates,
                "stats": stats.to_dict()
            }
        
    except Exception as e:
        error_msg = f"Embedding phase failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 3: Create embedding records
    # -------------------------------------------------------------------------
    try:
        logger.info("[Ingestion] Step 3: Creating embedding records")
        records = _create_embedding_records(
            candidates=candidates,
            vectors=vectors,
            success_indices=success_indices,
            topic_id=topic_id,
            prompt_text=prompt.text,
            subject=subject,
        )
        stats.records_created = len(records)
        logger.info(f"[Ingestion] Created {len(records)} embedding records")
        
    except Exception as e:
        error_msg = f"Record creation failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 4: Upsert to Pinecone
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 4: Upserting {len(records)} records to Pinecone")
        upsert_images(records)
        stats.upserted_count = len(records)
        
        logger.info(
            f"[Ingestion] ✅ Complete: indexed {stats.upserted_count} images for topic {topic_id}"
        )
        
    except Exception as e:
        error_msg = f"Pinecone upsert failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        # Records were created but not upserted
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Success
    # -------------------------------------------------------------------------
    return {
        "topic_id": topic_id,
        "indexed_count": stats.upserted_count,
        "candidates": candidates,
        "stats": stats.to_dict()
    }


def run_image_research_and_index_sync(
    prompt: UserPrompt,
    subject: str = "General",
    max_images: Optional[int] = None
) -> Dict[str, Any]:
    """
    Synchronous version of image research and indexing.
    
    See run_image_research_and_index for full documentation.
    """
    topic_id = _generate_topic_id(prompt.text)
    max_imgs = max_images or config.max_images_per_prompt
    stats = IngestionStats(topic_id=topic_id)
    
    logger.info(f"[Ingestion] Starting (sync) for topic_id={topic_id}, query='{prompt.text[:50]}...'")
    
    # -------------------------------------------------------------------------
    # Step 1: Research images
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 1: Researching images (subject={subject}, limit={max_imgs})")
        candidates = research_images(
            query=prompt.text,
            subject=subject,
            max_images=max_imgs
        )
        stats.candidates_found = len(candidates)
        
        if not candidates:
            logger.warning(f"[Ingestion] No images found for query: '{prompt.text}'")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": [],
                "stats": stats.to_dict()
            }
        
        logger.info(f"[Ingestion] Found {len(candidates)} candidate images")
        
    except Exception as e:
        error_msg = f"Research phase failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": [],
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 2: Generate embeddings (includes download)
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 2: Generating embeddings for {len(candidates)} images")
        stats.embedding_attempts = len(candidates)
        
        image_urls = [c.source_url for c in candidates]
        vectors, success_indices = embed_images_batch(image_urls)
        
        stats.embedding_successes = len(success_indices)
        stats.embedding_failures = len(candidates) - len(success_indices)
        
        logger.info(
            f"[Ingestion] Embeddings: {stats.embedding_successes}/{stats.embedding_attempts} succeeded, "
            f"{stats.embedding_failures} failed"
        )
        
        if not vectors:
            logger.warning("[Ingestion] No embeddings generated successfully")
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "candidates": candidates,
                "stats": stats.to_dict()
            }
        
    except Exception as e:
        error_msg = f"Embedding phase failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 3: Create embedding records
    # -------------------------------------------------------------------------
    try:
        logger.info("[Ingestion] Step 3: Creating embedding records")
        records = _create_embedding_records(
            candidates=candidates,
            vectors=vectors,
            success_indices=success_indices,
            topic_id=topic_id,
            prompt_text=prompt.text,
            subject=subject,
        )
        stats.records_created = len(records)
        logger.info(f"[Ingestion] Created {len(records)} embedding records")
        
    except Exception as e:
        error_msg = f"Record creation failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Step 4: Upsert to Pinecone
    # -------------------------------------------------------------------------
    try:
        logger.info(f"[Ingestion] Step 4: Upserting {len(records)} records to Pinecone")
        upsert_images(records)
        stats.upserted_count = len(records)
        
        logger.info(
            f"[Ingestion] ✅ Complete: indexed {stats.upserted_count} images for topic {topic_id}"
        )
        
    except Exception as e:
        error_msg = f"Pinecone upsert failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "candidates": candidates,
            "stats": stats.to_dict()
        }
    
    # -------------------------------------------------------------------------
    # Success
    # -------------------------------------------------------------------------
    return {
        "topic_id": topic_id,
        "indexed_count": stats.upserted_count,
        "candidates": candidates,
        "stats": stats.to_dict()
    }


def ingest_candidates(
    candidates: List[ImageCandidate],
    topic_id: str,
    prompt_text: str,
    subject: str = "General",
) -> Dict[str, Any]:
    """
    Ingest pre-researched candidates directly (skip research step).
    
    Useful when you already have ImageCandidates from another source.
    
    Args:
        candidates: List of ImageCandidate to process
        topic_id: Topic identifier for Pinecone filtering
        prompt_text: Original prompt for metadata
        subject: Subject area for metadata
        
    Returns:
        Dict with indexed_count, stats, etc.
    """
    stats = IngestionStats(topic_id=topic_id)
    stats.candidates_found = len(candidates)
    
    logger.info(f"[Ingestion] Direct ingest of {len(candidates)} candidates for topic {topic_id}")
    
    if not candidates:
        logger.warning("[Ingestion] No candidates to ingest")
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "stats": stats.to_dict()
        }
    
    # Embed
    try:
        stats.embedding_attempts = len(candidates)
        image_urls = [c.source_url for c in candidates]
        vectors, success_indices = embed_images_batch(image_urls)
        
        stats.embedding_successes = len(success_indices)
        stats.embedding_failures = len(candidates) - len(success_indices)
        
        logger.info(
            f"[Ingestion] Embeddings: {stats.embedding_successes}/{stats.embedding_attempts} succeeded"
        )
        
        if not vectors:
            return {
                "topic_id": topic_id,
                "indexed_count": 0,
                "stats": stats.to_dict()
            }
        
    except Exception as e:
        error_msg = f"Embedding failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "stats": stats.to_dict()
        }
    
    # Create records
    records = _create_embedding_records(
        candidates=candidates,
        vectors=vectors,
        success_indices=success_indices,
        topic_id=topic_id,
        prompt_text=prompt_text,
        subject=subject,
    )
    stats.records_created = len(records)
    
    # Upsert
    try:
        upsert_images(records)
        stats.upserted_count = len(records)
        logger.info(f"[Ingestion] ✅ Upserted {stats.upserted_count} records")
        
    except Exception as e:
        error_msg = f"Upsert failed: {e}"
        logger.error(f"[Ingestion] {error_msg}")
        stats.errors.append(error_msg)
        return {
            "topic_id": topic_id,
            "indexed_count": 0,
            "stats": stats.to_dict()
        }
    
    return {
        "topic_id": topic_id,
        "indexed_count": stats.upserted_count,
        "stats": stats.to_dict()
    }
