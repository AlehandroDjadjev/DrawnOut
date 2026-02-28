"""
Main orchestrator pipeline.

Coordinates all pipeline steps to generate complete lessons with images.

Pipeline flow:
1. Parallel: Whiteboard image pipeline prefetch + Script generation
2. Parse IMAGE tags from script
3. Batch-resolve all tag prompts via the whiteboard image pipeline
4. Inject resolved images into script
5. Build LessonDocument

The whiteboard image pipeline (whiteboard_backend/image-pipeline/) replaces
the old image-ingestion + Pinecone-resolver path. It returns the full triad
for each image: base64 image, SigLIP embedding, and vectorized strokes.
"""
import logging
from dataclasses import dataclass, field
from typing import Optional, Dict, Any, List

from lesson_pipeline.types import (
    UserPrompt,
    LessonDocument,
    ResolvedImage,
    lesson_document_to_dict,
)
from lesson_pipeline.utils.image_tags import (
    parse_image_tags,
    inject_resolved_images,
    build_image_slots,
)
from lesson_pipeline.services.script_writer import generate_script
from lesson_pipeline.services.whiteboard_image_service import (
    WhiteboardPipelinePrefetch,
    call_whiteboard_pipeline,
    pick_best_entry_for_tag,
)
from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Default timeout waiting for the whiteboard pipeline prefetch (seconds).
# The pipeline can be slow on first run (model load + research); cached runs
# are much faster.
DEFAULT_VECTOR_SUBPROCESS_TIMEOUT = 600.0


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
    Generate a complete lesson with images sourced from the whiteboard pipeline.

    Pipeline:
    1. Kick off whiteboard image pipeline prefetch in background (parallel with
       script generation). The prefetch calls the whiteboard image-pipeline API
       with the main topic so Qwen/SigLIP research + vectorization runs while
       the LLM writes the script.
    2. Generate script (contains [IMAGE ...] tags).
    3. Parse IMAGE tags from the generated script.
    4. Batch-call the whiteboard image pipeline for all tag prompts.
       The main-topic images from step 1 are now cached in Pinecone so most
       tag lookups are instant.
    5. Map each tag to its best matching image entry (image_b64, embedding,
       strokes) and build ResolvedImage objects.
    6. Inject images into script and return LessonDocument.

    Args:
        prompt_text: Lesson topic / main user query
        subject: Subject area (e.g., "Biology", "Physics")
        duration_target: Target duration in seconds
        vector_timeout: Max seconds to wait for whiteboard pipeline (None = config default)
        use_existing_images: If True, skip the prefetch — use whatever images
            the whiteboard pipeline already has cached in Pinecone.

    Returns:
        LessonDocument with complete lesson and images.
    """
    stats = OrchestrationStats()
    timeout = vector_timeout or DEFAULT_VECTOR_SUBPROCESS_TIMEOUT

    logger.info(
        f"=== Starting lesson generation: {prompt_text!r} "
        f"subject={subject!r} use_existing={use_existing_images} ==="
    )

    prompt = UserPrompt(text=prompt_text)

    # -------------------------------------------------------------------------
    # STEP 1: Kick off image pipeline in background (parallel with script gen)
    #
    # This call does three things on the whiteboard_backend side:
    #   • Researches images for the topic (DuckDuckGo / Wikimedia / etc.)
    #   • Runs Qwen selection + SigLIP embedding + stroke vectorization
    #   • Upserts embeddings into the whiteboard Pinecone index
    #
    # We don't use the return value here — we only want Pinecone populated
    # so that the per-tag similarity queries in Step 4 find something.
    # -------------------------------------------------------------------------
    prefetch: Optional[WhiteboardPipelinePrefetch] = None

    if not use_existing_images:
        logger.info(
            "[Orchestrator] Step 1: Pre-populating whiteboard image DB "
            "(background, parallel with script generation)..."
        )
        prefetch = WhiteboardPipelinePrefetch(
            {prompt_text: subject},
            top_n_per_prompt=2,  # just enough to trigger research + Pinecone upsert
        )
    else:
        logger.info(
            "[Orchestrator] Step 1: Skipping pre-populate — using existing cached images."
        )

    # -------------------------------------------------------------------------
    # STEP 2: Generate script (while image pipeline runs in background)
    # -------------------------------------------------------------------------
    script_draft = None
    try:
        script_draft = generate_script(prompt, duration_target)
        if script_draft:
            stats.script_generated = True
            stats.script_length = len(script_draft.content)
            logger.info(
                f"[Orchestrator] ✓ Script generated: {stats.script_length} chars"
            )
    except Exception as exc:
        error_msg = f"Script generation failed: {exc}"
        logger.error(f"[Orchestrator] {error_msg}")
        stats.errors.append(error_msg)

    # Wait for the image pipeline to finish so Pinecone is fully populated
    # before we run the per-tag similarity queries.
    if prefetch is not None:
        logger.info(
            "[Orchestrator] Waiting for image pipeline to finish indexing..."
        )
        prefetch_result = prefetch.get(timeout=timeout)
        stats.images_indexed = sum(len(v) for v in prefetch_result.values())
        logger.info(
            f"[Orchestrator] ✓ Image DB ready: "
            f"{stats.images_indexed} images indexed for main topic"
        )
    else:
        stats.images_indexed = 0

    if not script_draft:
        logger.error("[Orchestrator] Script generation failed — returning error document")
        return LessonDocument(
            prompt_id=prompt.id,
            content="Failed to generate lesson script. Please try again.",
            images=[],
            topic_id=stats.topic_id,
            indexed_image_count=stats.images_indexed,
        )

    # -------------------------------------------------------------------------
    # STEP 3: Parse IMAGE tags from script
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 3: Parsing IMAGE tags from script...")

    cleaned_content, tags = parse_image_tags(script_draft.content)
    stats.image_tags_found = len(tags)
    image_slots = build_image_slots(tags)

    logger.info(f"[Orchestrator] Found {stats.image_tags_found} IMAGE tags")

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
    # STEP 4: Resolve each IMAGE tag via Pinecone embedding similarity
    #
    # Call image-pipeline with all tag prompts in one batch.
    # Because the main topic was already indexed in Step 1, these calls
    # hit the Pinecone cache:
    #   fetch_processed_ids_for_prompt(tag.prompt) embeds the text with
    #   MiniLM/SigLIP and finds the most semantically similar image in the DB.
    # The pipeline then loads the saved stroke JSON for each matched image.
    # -------------------------------------------------------------------------
    logger.info(
        "[Orchestrator] Step 4: Resolving IMAGE tags via embedding similarity..."
    )

    tag_prompt_map: Dict[str, str] = {
        tag.prompt: subject for tag in tags if tag.prompt
    }

    tag_pipeline_result = call_whiteboard_pipeline(
        tag_prompt_map,
        top_n_per_prompt=1,  # one best match per tag is enough for drawing
    )

    stats.images_resolved = sum(
        1 for tag in tags
        if pick_best_entry_for_tag(tag.prompt, tag_pipeline_result) is not None
    )
    logger.info(
        f"[Orchestrator] Resolved {stats.images_resolved}/{stats.image_tags_found} tags"
    )

    # -------------------------------------------------------------------------
    # STEP 5: Build ResolvedImage objects
    #
    # Each entry from the pipeline has:
    #   id        — processed_id (maps to StrokeVectors/{id}.json on disk)
    #   strokes   — full cubic Bézier stroke JSON, ready for the whiteboard
    #   embedding — SigLIP vector (for downstream use)
    #
    # base_image_url is intentionally left empty — the whiteboard draws using
    # strokes, not by rendering the original raster image.
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 5: Building ResolvedImage objects...")

    resolved_images: List[ResolvedImage] = []
    for tag in tags:
        entry = pick_best_entry_for_tag(tag.prompt, tag_pipeline_result)

        if entry is None:
            logger.warning(
                f"[Orchestrator] No image found for tag: {tag.prompt!r}"
            )
            resolved_images.append(
                ResolvedImage(tag=tag, base_image_url="", final_image_url="", metadata={})
            )
            continue

        resolved = ResolvedImage(
            tag=tag,
            base_image_url="",   # whiteboard draws from strokes, not a URL
            final_image_url="",
            vector_id=entry.get("id"),
            metadata={
                "pipeline_id": entry.get("id"),
                "strokes": entry.get("strokes"),    # cubic Bézier JSON → whiteboard draws this
                "embedding": entry.get("embedding"), # SigLIP vector
            },
        )
        resolved_images.append(resolved)

    stats.images_transformed = len(resolved_images)
    logger.info(f"[Orchestrator] Prepared {stats.images_transformed} images")

    # -------------------------------------------------------------------------
    # STEP 6: Inject images into script
    # -------------------------------------------------------------------------
    logger.info("[Orchestrator] Step 6: Injecting images into script...")

    final_content = inject_resolved_images(cleaned_content, resolved_images)

    lesson = LessonDocument(
        prompt_id=prompt.id,
        content=final_content,
        images=resolved_images,
        topic_id=stats.topic_id,
        indexed_image_count=stats.images_indexed,
        image_slots=image_slots,
    )

    logger.info("=== Lesson generation complete ===")
    logger.info(f"[Orchestrator] Stats: {stats.to_dict()}")

    return lesson


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
