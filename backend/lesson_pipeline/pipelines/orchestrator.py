"""
Main orchestrator pipeline.

Coordinates all pipeline steps to generate complete lessons with images.

Pipeline flow:
1. Parallel: Image research + Script generation
2. Parse IMAGE tags from script
3. Resolve tags to base images (Pinecone vector search + keyword fallback)
4. Inject resolved images into script
5. Build LessonDocument
"""
import logging
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List

from lesson_pipeline.types import (
    UserPrompt,
    LessonDocument,
    ImageCandidate,
    ResolvedImage,
    lesson_document_to_dict,
)
from lesson_pipeline.utils.image_tags import (
    parse_image_tags,
    inject_resolved_images,
    build_image_slots,
)
from lesson_pipeline.pipelines.image_vector_subprocess import (
    start_image_vector_subprocess,
    ImageVectorSubprocess,
)
from lesson_pipeline.pipelines.image_resolver import resolve_image_tags_for_topic
from lesson_pipeline.services.script_writer import generate_script
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Default timeout for waiting on image indexing (seconds)
DEFAULT_VECTOR_SUBPROCESS_TIMEOUT = 120.0


@dataclass
class OrchestrationStats:
    """Statistics from the orchestration pipeline."""
    script_generated: bool = False
    script_length: int = 0
    image_tags_found: int = 0
    images_indexed: int = 0
    images_resolved: int = 0
    images_transformed: int = 0
    topic_id: str = ""
    errors: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "script_generated": self.script_generated,
            "script_length": self.script_length,
            "image_tags_found": self.image_tags_found,
            "images_indexed": self.images_indexed,
            "images_resolved": self.images_resolved,
            "images_transformed": self.images_transformed,
            "topic_id": self.topic_id,
            "errors": self.errors,
        }


def generate_lesson(
    prompt_text: str,
    subject: str = "General",
    duration_target: float = 60.0,
    vector_timeout: Optional[float] = None,
    use_existing_images: bool = False,
) -> LessonDocument:
    """
    Generate a complete lesson with intelligently matched and transformed images.

    When use_existing_images=True, skips image research and indexing; resolves
    images from Pinecone using topic_id (same prompt = same topic). Use for
    fast repeat lessons or when DB already has images for this topic.

    Pipeline:
    1. If use_existing_images: skip research, compute topic_id only
       Else: parallel image research (background) + script generation
    2. Parse IMAGE tags from generated script
    3. Resolve tags to base images (Pinecone + keyword fallback)
    4. Inject resolved images into script content

    Args:
        prompt_text: Lesson topic
        subject: Subject area (e.g., "Biology", "Physics")
        duration_target: Target duration in seconds
        vector_timeout: Max seconds to wait for image indexing (None = config default)
        use_existing_images: If True, skip research phase and use existing Pinecone images only

    Returns:
        LessonDocument with complete lesson and images
    """
    stats = OrchestrationStats()
    timeout = vector_timeout or DEFAULT_VECTOR_SUBPROCESS_TIMEOUT

    logger.info(f"=== Starting lesson generation for: {prompt_text} (use_existing={use_existing_images}) ===")

    # Create user prompt
    prompt = UserPrompt(text=prompt_text)

    if use_existing_images:
        from lesson_pipeline.pipelines.image_ingestion import _generate_topic_id
        stats.topic_id = _generate_topic_id(prompt_text)
        stats.images_indexed = 0
        image_index_info = {
            "topic_id": stats.topic_id,
            "indexed_count": 0,
            "candidates": [],
        }
        logger.info(f"[Orchestrator] Skipping research, using existing images for topic_id={stats.topic_id}")
    else:
        # -------------------------------------------------------------------------
        # STEP 1: Kick off background image vector subprocess + script generation
        # -------------------------------------------------------------------------
        logger.info("[Orchestrator] Step 1: Starting parallel image research + script generation...")
        vector_subprocess = start_image_vector_subprocess(prompt, subject)

    script_draft = None
    try:
        script_draft = generate_script(prompt, duration_target)
        if script_draft:
            stats.script_generated = True
            stats.script_length = len(script_draft.content)
            logger.info(f"[Orchestrator] ✓ Script generated: {stats.script_length} characters")
    except Exception as e:
        error_msg = f"Script generation failed: {e}"
        logger.error(f"[Orchestrator] {error_msg}")
        stats.errors.append(error_msg)

    if not use_existing_images:
        image_index_info = _wait_for_vector_subprocess(vector_subprocess, timeout)

    stats.images_indexed = image_index_info.get("indexed_count", 0)
    stats.topic_id = image_index_info.get("topic_id", stats.topic_id)
    
    logger.info(
        f"[Orchestrator] ✓ Image indexing complete: {stats.images_indexed} images indexed"
    )
    
    # Check if script generation succeeded
    if not script_draft:
        logger.error("[Orchestrator] Script generation failed - returning error document")
        return LessonDocument(
            prompt_id=prompt.id,
            content="Failed to generate lesson script. Please try again.",
            images=[],
            topic_id=stats.topic_id,
            indexed_image_count=stats.images_indexed,
        )
    
    # -------------------------------------------------------------------------
    # STEP 2: Parse IMAGE tags from script
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 2: Parsing IMAGE tags from script...")
    
    cleaned_content, tags = parse_image_tags(script_draft.content)
    stats.image_tags_found = len(tags)
    
    logger.info(f"[Orchestrator] Found {stats.image_tags_found} IMAGE tags")
    
    image_slots = build_image_slots(tags)
    
    if not tags:
        logger.warning("[Orchestrator] No IMAGE tags found in script")
        return LessonDocument(
            prompt_id=prompt.id,
            content=script_draft.content,
            images=[],
            topic_id=stats.topic_id,
            indexed_image_count=stats.images_indexed,
            image_slots=image_slots,
        )
    
    # -------------------------------------------------------------------------
    # STEP 3: Resolve tags to base images from Pinecone
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 3: Resolving IMAGE tags to base images...")
    
    # Get candidates for keyword fallback
    fallback_candidates: List[ImageCandidate] = image_index_info.get('candidates', [])
    
    resolved_base = resolve_image_tags_for_topic(
        topic_id=stats.topic_id,
        tags=tags,
        top_k=3,
        fallback_candidates=fallback_candidates,
    )
    
    stats.images_resolved = len([r for r in resolved_base if r.get('base_image_url')])
    logger.info(f"[Orchestrator] Resolved {stats.images_resolved}/{stats.image_tags_found} tags")
    
    # -------------------------------------------------------------------------
    # STEP 4: Build ResolvedImage objects from base images (no transformation)
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 4: Preparing resolved images...")
    
    resolved_images: List[ResolvedImage] = []
    for item in resolved_base:
        tag = item['tag']
        base_image_url = item['base_image_url']
        resolved = ResolvedImage(
            tag=tag,
            base_image_url=base_image_url,
            final_image_url=base_image_url or "",
            metadata={
                'base': item.get('base_metadata'),
            }
        )
        resolved_images.append(resolved)
    
    stats.images_transformed = len(resolved_images)
    logger.info(f"[Orchestrator] Prepared {stats.images_transformed} images")
    
    # -------------------------------------------------------------------------
    # STEP 5: Inject final images into script
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 5: Injecting images into script...")
    
    final_content = inject_resolved_images(cleaned_content, resolved_images)
    
    # -------------------------------------------------------------------------
    # Build final lesson document
    # -------------------------------------------------------------------------
    lesson = LessonDocument(
        prompt_id=prompt.id,
        content=final_content,
        images=resolved_images,
        topic_id=stats.topic_id,
        indexed_image_count=stats.images_indexed,
        image_slots=image_slots,
    )
    
    logger.info(f"=== Lesson generation complete ===")
    logger.info(f"[Orchestrator] Stats: {stats.to_dict()}")
    
    return lesson


def _wait_for_vector_subprocess(
    subprocess: ImageVectorSubprocess,
    timeout: float
) -> Dict[str, Any]:
    """
    Wait for vector subprocess with timeout and graceful fallback.
    
    If the subprocess times out or fails, returns a fallback payload
    so the pipeline can continue without images.
    """
    try:
        result = subprocess.wait_for_result(timeout=timeout)
        
        if result:
            return result
        
        logger.warning("[Orchestrator] Vector subprocess returned empty result")
        return _fallback_index_info()
        
    except Exception as e:
        logger.warning(f"[Orchestrator] Vector subprocess failed/timed out: {e}")
        return _fallback_index_info()


def _fallback_index_info() -> Dict[str, Any]:
    """Return fallback payload when image indexing fails."""
    return {
        "topic_id": "",
        "indexed_count": 0,
        "candidates": [],
    }


def generate_lesson_json(
    prompt_text: str,
    subject: str = "General",
    duration_target: float = 60.0,
    vector_timeout: Optional[float] = None,
    use_existing_images: bool = False,
) -> Dict[str, Any]:
    """
    Generate lesson and return as JSON-serializable dict.

    Args:
        prompt_text: Lesson topic
        subject: Subject area
        duration_target: Target duration
        vector_timeout: Max seconds to wait for image indexing
        use_existing_images: Skip research phase and use existing Pinecone images only

    Returns:
        Dict representation of LessonDocument
    """
    lesson = generate_lesson(
        prompt_text,
        subject,
        duration_target,
        vector_timeout,
        use_existing_images,
    )
    return lesson_document_to_dict(lesson)


def generate_lesson_async_safe(
    prompt_text: str,
    subject: str = "General",
    duration_target: float = 60.0,
    use_existing_images: bool = False,
) -> Dict[str, Any]:
    """
    Generate lesson with extra error handling for API use.

    Returns a result dict that always has 'success' and either 'data' or 'error'.
    """
    try:
        result = generate_lesson_json(
            prompt_text, subject, duration_target, use_existing_images=use_existing_images
        )
        return {
            "success": True,
            "data": result,
        }
    except Exception as e:
        logger.error(f"[Orchestrator] Lesson generation failed: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return {
            "success": False,
            "error": str(e),
            "data": {
                "id": "",
                "prompt_id": "",
                "content": f"Lesson generation failed: {e}",
                "images": [],
                "topic_id": "",
                "indexed_image_count": 0,
                "image_slots": [],
            }
        }
