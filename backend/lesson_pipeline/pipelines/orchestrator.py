"""
Main orchestrator pipeline.

Coordinates all pipeline steps to generate complete lessons with images.
"""
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional

from lesson_pipeline.types import UserPrompt, LessonDocument, lesson_document_to_dict
from lesson_pipeline.utils.image_tags import parse_image_tags, inject_resolved_images
from lesson_pipeline.pipelines.image_ingestion import run_image_research_and_index_sync
from lesson_pipeline.pipelines.image_resolver import resolve_image_tags_for_topic
from lesson_pipeline.pipelines.image_transformation import transform_resolved_images
from lesson_pipeline.services.script_writer import generate_script

logger = logging.getLogger(__name__)


def generate_lesson(
    prompt_text: str,
    subject: str = "General",
    duration_target: float = 60.0
) -> LessonDocument:
    """
    Generate a complete lesson with intelligently matched and transformed images.
    
    This orchestrates:
    1. Parallel: Image research + Script generation
    2. Parse IMAGE tags
    3. Resolve tags to base images (Pinecone)
    4. Transform images (img2img)
    5. Inject into script
    
    Args:
        prompt_text: Lesson topic
        subject: Subject area
        duration_target: Target duration
    
    Returns:
        LessonDocument with complete lesson and images
    """
    logger.info(f"=== Starting lesson generation for: {prompt_text} ===")
    
    # Create user prompt
    prompt = UserPrompt(text=prompt_text)
    
    # STEP 1: Run image research and script generation IN PARALLEL
    logger.info("Step 1: Running image research and script generation in parallel...")
    
    image_index_info = None
    script_draft = None
    
    with ThreadPoolExecutor(max_workers=2) as executor:
        # Submit both tasks
        future_images = executor.submit(
            run_image_research_and_index_sync,
            prompt,
            subject
        )
        future_script = executor.submit(
            generate_script,
            prompt,
            duration_target
        )
        
        # Wait for both to complete
        for future in as_completed([future_images, future_script]):
            try:
                if future == future_images:
                    image_index_info = future.result()
                    logger.info(f"✓ Image research complete: {image_index_info['indexed_count']} images indexed")
                elif future == future_script:
                    script_draft = future.result()
                    logger.info(f"✓ Script generation complete: {len(script_draft.content)} characters")
            except Exception as e:
                logger.error(f"Parallel task failed: {e}")
    
    # Check if we got results
    if not script_draft:
        logger.error("Script generation failed")
        return LessonDocument(
            prompt_id=prompt.id,
            content="Failed to generate lesson script",
            images=[],
            topic_id="",
            indexed_image_count=0
        )
    
    if not image_index_info:
        logger.warning("Image research failed, continuing without images")
        image_index_info = {
            "topic_id": "",
            "indexed_count": 0,
            "candidates": []
        }
    
    # STEP 2: Parse IMAGE tags from script
    logger.info("Step 2: Parsing IMAGE tags from script...")
    cleaned_content, tags = parse_image_tags(script_draft.content)
    logger.info(f"Found {len(tags)} IMAGE tags")
    
    if not tags:
        logger.warning("No IMAGE tags found in script")
        # Return script as-is
        return LessonDocument(
            prompt_id=prompt.id,
            content=script_draft.content,
            images=[],
            topic_id=image_index_info['topic_id'],
            indexed_image_count=image_index_info['indexed_count']
        )
    
    # STEP 3: Resolve tags to base images from Pinecone
    logger.info("Step 3: Resolving IMAGE tags to base images...")
    resolved_base = resolve_image_tags_for_topic(
        topic_id=image_index_info['topic_id'],
        tags=tags,
        top_k=3
    )
    logger.info(f"Resolved {len(resolved_base)} tags")
    
    # STEP 4: Transform images using img2img
    logger.info("Step 4: Transforming images...")
    transformed = transform_resolved_images(resolved_base)
    logger.info(f"Transformed {len(transformed)} images")
    
    # STEP 5: Inject final images into script
    logger.info("Step 5: Injecting images into script...")
    final_content = inject_resolved_images(cleaned_content, transformed)
    
    # Create final lesson document
    lesson = LessonDocument(
        prompt_id=prompt.id,
        content=final_content,
        images=transformed,
        topic_id=image_index_info['topic_id'],
        indexed_image_count=image_index_info['indexed_count']
    )
    
    logger.info(f"=== Lesson generation complete ===")
    logger.info(f"Total images: {len(transformed)}")
    logger.info(f"Content length: {len(final_content)} characters")
    
    return lesson


def generate_lesson_json(
    prompt_text: str,
    subject: str = "General",
    duration_target: float = 60.0
) -> dict:
    """
    Generate lesson and return as JSON-serializable dict.
    
    Args:
        prompt_text: Lesson topic
        subject: Subject area
        duration_target: Target duration
    
    Returns:
        Dict representation of LessonDocument
    """
    lesson = generate_lesson(prompt_text, subject, duration_target)
    return lesson_document_to_dict(lesson)

