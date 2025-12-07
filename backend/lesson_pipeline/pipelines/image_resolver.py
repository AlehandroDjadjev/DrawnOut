"""
Image tag resolution pipeline.

Resolves IMAGE tags to base images using Pinecone semantic search.
"""
import logging
from typing import List, Dict, Tuple

from lesson_pipeline.types import ImageTag
from lesson_pipeline.services.embeddings import embed_text
from lesson_pipeline.services.vector_store import query_images_by_text

logger = logging.getLogger(__name__)


def resolve_image_tags_for_topic(
    topic_id: str,
    tags: List[ImageTag],
    top_k: int = 3
) -> List[Dict]:
    """
    Resolve IMAGE tags to base images using semantic search.
    
    Args:
        topic_id: Topic ID to filter by
        tags: List of ImageTag to resolve
        top_k: Number of candidates per tag
    
    Returns:
        List of dicts with tag, base_image_url, and base_metadata
    """
    logger.info(f"Resolving {len(tags)} image tags for topic {topic_id}")
    
    results = []
    
    for tag in tags:
        try:
            logger.debug(f"Resolving tag: {tag.id} - {tag.prompt}")
            
            # 1. Embed tag prompt
            query_text = tag.query or tag.prompt
            vector = embed_text(query_text)
            
            # 2. Query Pinecone
            matches = query_images_by_text(
                text_embedding=vector,
                topic_id=topic_id,
                top_k=top_k
            )
            
            if not matches:
                logger.warning(f"No matches found for tag {tag.id}")
                results.append({
                    "tag": tag,
                    "base_image_url": "",
                    "base_metadata": None,
                    "needs_text_to_image": True
                })
                continue
            
            # 3. Pick best match
            best_match = matches[0]
            
            results.append({
                "tag": tag,
                "base_image_url": best_match.image_url,
                "base_metadata": best_match.metadata,
                "needs_text_to_image": False,
                "vector_id": best_match.id,
            })
            
            logger.info(f"Resolved tag {tag.id} to image: {best_match.image_url[:50]}...")
            
        except Exception as e:
            logger.error(f"Failed to resolve tag {tag.id}: {e}")
            results.append({
                "tag": tag,
                "base_image_url": "",
                "base_metadata": None,
                "needs_text_to_image": True,
                "vector_id": None,
            })
    
    logger.info(f"Resolved {len([r for r in results if r['base_image_url']])} / {len(tags)} tags")
    
    return results









