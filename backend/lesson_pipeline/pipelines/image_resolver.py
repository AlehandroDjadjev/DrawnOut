"""
Image tag resolution pipeline.

Resolves IMAGE tags to base images using Pinecone semantic search.

Flow:
1. For each ImageTag or ScriptImageRequest:
   - embed_text(prompt) → 1536-dimensional vector
   - query Pinecone via query_images_by_text(vector, topic_id, top_k)
   - Choose best match → ResolvedImage

Fallbacks:
- If no Pinecone matches: try keyword matching against available candidates
- If still nothing: return empty base_image_url (downstream skips gracefully)
"""
import logging
import re
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Union

from lesson_pipeline.types import (
    ImageTag,
    ScriptImageRequest,
    ResolvedImage,
    ImageCandidate,
    ImageEmbeddingRecord,
)
from lesson_pipeline.services.embeddings import embed_text
from lesson_pipeline.services.vector_store import query_images_by_text

logger = logging.getLogger(__name__)


@dataclass
class ResolutionStats:
    """Statistics from resolution pipeline."""
    total_tags: int = 0
    resolved_via_vector: int = 0
    resolved_via_keyword: int = 0
    unresolved: int = 0
    errors: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_tags": self.total_tags,
            "resolved_via_vector": self.resolved_via_vector,
            "resolved_via_keyword": self.resolved_via_keyword,
            "unresolved": self.unresolved,
            "errors": self.errors,
        }


def _extract_keywords(text: str) -> List[str]:
    """
    Extract keywords from text for fallback matching.
    
    Removes common words and returns significant terms.
    """
    # Common stop words to filter out
    stop_words = {
        'a', 'an', 'the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
        'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
        'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
        'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'need',
        'this', 'that', 'these', 'those', 'it', 'its', 'image', 'picture',
        'diagram', 'illustration', 'show', 'showing', 'display', 'displaying',
    }
    
    # Tokenize and filter
    words = re.findall(r'\b[a-zA-Z]{3,}\b', text.lower())
    keywords = [w for w in words if w not in stop_words]
    
    return keywords


def _keyword_score(keywords: List[str], candidate: ImageCandidate) -> int:
    """
    Score a candidate based on keyword matches in its metadata.
    
    Higher score = better match.
    """
    score = 0
    
    # Build searchable text from candidate
    searchable = []
    if candidate.title:
        searchable.append(candidate.title.lower())
    if candidate.description:
        searchable.append(candidate.description.lower())
    if candidate.tags:
        searchable.extend([t.lower() for t in candidate.tags])
    if candidate.metadata:
        for v in candidate.metadata.values():
            if isinstance(v, str):
                searchable.append(v.lower())
    
    search_text = ' '.join(searchable)
    
    # Count keyword matches
    for keyword in keywords:
        if keyword in search_text:
            score += 1
    
    return score


def _find_best_keyword_match(
    prompt: str,
    candidates: List[ImageCandidate]
) -> Optional[ImageCandidate]:
    """
    Find the best candidate by keyword matching.
    
    Returns None if no candidates score above 0.
    """
    if not candidates:
        return None
    
    keywords = _extract_keywords(prompt)
    if not keywords:
        return None
    
    scored = [(c, _keyword_score(keywords, c)) for c in candidates]
    scored.sort(key=lambda x: x[1], reverse=True)
    
    best_candidate, best_score = scored[0]
    
    if best_score > 0:
        logger.debug(f"Keyword fallback found match with score {best_score}")
        return best_candidate
    
    return None


def _get_prompt_from_tag(tag: Union[ImageTag, ScriptImageRequest]) -> str:
    """Extract the search prompt from a tag or request."""
    if isinstance(tag, ImageTag):
        return tag.query or tag.prompt
    elif isinstance(tag, ScriptImageRequest):
        return tag.prompt
    else:
        # Duck typing fallback
        return getattr(tag, 'query', None) or getattr(tag, 'prompt', '')


def _get_tag_id(tag: Union[ImageTag, ScriptImageRequest]) -> str:
    """Extract ID from a tag or request."""
    return getattr(tag, 'id', 'unknown')


def resolve_image_tags_for_topic(
    topic_id: str,
    tags: List[Union[ImageTag, ScriptImageRequest]],
    top_k: int = 3,
    fallback_candidates: Optional[List[ImageCandidate]] = None,
) -> List[Dict[str, Any]]:
    """
    Resolve IMAGE tags to base images using semantic search.
    
    Pipeline:
    1. Embed tag prompt → 1536-d vector
    2. Query Pinecone with topic filter
    3. If no matches, try keyword fallback against candidates
    4. Return resolution results
    
    Args:
        topic_id: Topic ID to filter Pinecone queries
        tags: List of ImageTag or ScriptImageRequest to resolve
        top_k: Number of candidates to retrieve per query
        fallback_candidates: Optional list of ImageCandidate for keyword fallback
    
    Returns:
        List of dicts with:
            - tag: The original tag
            - base_image_url: URL of matched image (empty if unresolved)
            - base_metadata: Metadata from matched record
            - needs_text_to_image: True if no image found
            - vector_id: Pinecone record ID (if vector match)
            - resolution_method: "vector" | "keyword" | None
    """
    stats = ResolutionStats(total_tags=len(tags))
    results: List[Dict[str, Any]] = []
    
    logger.info(f"[Resolver] Resolving {len(tags)} image tags for topic {topic_id}")
    
    for tag in tags:
        tag_id = _get_tag_id(tag)
        prompt = _get_prompt_from_tag(tag)
        
        try:
            logger.debug(f"[Resolver] Processing tag: {tag_id} - '{prompt[:50]}...'")
            
            # -----------------------------------------------------------------
            # Step 1: Embed the tag prompt
            # -----------------------------------------------------------------
            vector = embed_text(prompt)
            
            # -----------------------------------------------------------------
            # Step 2: Query Pinecone for similar images
            # -----------------------------------------------------------------
            matches = query_images_by_text(
                text_embedding=vector,
                topic_id=topic_id,
                top_k=top_k
            )
            
            # -----------------------------------------------------------------
            # Step 3: Check for matches
            # -----------------------------------------------------------------
            if matches:
                best_match = matches[0]
                
                results.append({
                    "tag": tag,
                    "base_image_url": best_match.image_url,
                    "base_metadata": best_match.metadata,
                    "needs_text_to_image": False,
                    "vector_id": best_match.id,
                    "resolution_method": "vector",
                })
                
                stats.resolved_via_vector += 1
                logger.info(f"[Resolver] Tag {tag_id}: vector match → {best_match.image_url[:60]}...")
                continue
            
            # -----------------------------------------------------------------
            # Step 4: Fallback to keyword matching
            # -----------------------------------------------------------------
            if fallback_candidates:
                keyword_match = _find_best_keyword_match(prompt, fallback_candidates)
                
                if keyword_match:
                    results.append({
                        "tag": tag,
                        "base_image_url": keyword_match.source_url,
                        "base_metadata": {
                            "title": keyword_match.title,
                            "description": keyword_match.description,
                            "source": keyword_match.source,
                        },
                        "needs_text_to_image": False,
                        "vector_id": None,
                        "resolution_method": "keyword",
                    })
                    
                    stats.resolved_via_keyword += 1
                    logger.info(f"[Resolver] Tag {tag_id}: keyword fallback → {keyword_match.source_url[:60]}...")
                    continue
            
            # -----------------------------------------------------------------
            # Step 5: No match found - mark for text-to-image generation
            # -----------------------------------------------------------------
            logger.warning(f"[Resolver] Tag {tag_id}: no matches found")
            results.append({
                "tag": tag,
                "base_image_url": "",
                "base_metadata": None,
                "needs_text_to_image": True,
                "vector_id": None,
                "resolution_method": None,
            })
            stats.unresolved += 1
            
        except Exception as e:
            logger.error(f"[Resolver] Failed to resolve tag {tag_id}: {e}")
            results.append({
                "tag": tag,
                "base_image_url": "",
                "base_metadata": None,
                "needs_text_to_image": True,
                "vector_id": None,
                "resolution_method": None,
                "error": str(e),
            })
            stats.errors += 1
    
    # Log summary
    logger.info(
        f"[Resolver] Complete: {stats.resolved_via_vector} vector, "
        f"{stats.resolved_via_keyword} keyword, "
        f"{stats.unresolved} unresolved, "
        f"{stats.errors} errors"
    )
    
    return results


def resolve_to_resolved_images(
    topic_id: str,
    tags: List[ImageTag],
    top_k: int = 3,
    fallback_candidates: Optional[List[ImageCandidate]] = None,
) -> List[ResolvedImage]:
    """
    Resolve IMAGE tags and return ResolvedImage objects.
    
    This is the typed version that returns proper ResolvedImage dataclass instances.
    
    Args:
        topic_id: Topic ID for Pinecone filtering
        tags: List of ImageTag to resolve
        top_k: Number of candidates per query
        fallback_candidates: Optional candidates for keyword fallback
        
    Returns:
        List of ResolvedImage (only successfully resolved tags)
    """
    results = resolve_image_tags_for_topic(
        topic_id=topic_id,
        tags=tags,
        top_k=top_k,
        fallback_candidates=fallback_candidates,
    )
    
    resolved_images: List[ResolvedImage] = []
    
    for result in results:
        if result.get("base_image_url"):
            tag = result["tag"]
            
            # Ensure tag is an ImageTag
            if not isinstance(tag, ImageTag):
                # Convert ScriptImageRequest to minimal ImageTag
                tag = ImageTag(
                    id=tag.id,
                    prompt=tag.prompt,
                )
            
            resolved = ResolvedImage(
                tag=tag,
                base_image_url=result["base_image_url"],
                final_image_url=result["base_image_url"],  # Will be transformed later
                vector_id=result.get("vector_id"),
                metadata=result.get("base_metadata") or {},
            )
            resolved_images.append(resolved)
    
    return resolved_images


def resolve_single_tag(
    tag: Union[ImageTag, ScriptImageRequest],
    topic_id: str,
    top_k: int = 3,
    fallback_candidates: Optional[List[ImageCandidate]] = None,
) -> Dict[str, Any]:
    """
    Resolve a single tag. Convenience function.
    
    Returns:
        Resolution result dict
    """
    results = resolve_image_tags_for_topic(
        topic_id=topic_id,
        tags=[tag],
        top_k=top_k,
        fallback_candidates=fallback_candidates,
    )
    return results[0] if results else {
        "tag": tag,
        "base_image_url": "",
        "base_metadata": None,
        "needs_text_to_image": True,
        "vector_id": None,
        "resolution_method": None,
    }

