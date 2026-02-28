"""
HTTP client for the whiteboard_backend image pipeline.

Calls POST /api/wb/pipeline/image-pipeline/ and returns the enriched
result: { prompt: [{ id, image_b64, image_mime, embedding, strokes }] }

Used by the orchestrator to replace the old image-ingestion + Pinecone
resolver path with the richer whiteboard pipeline (Qwen + SigLIP + stroke
vectorization).
"""
import json
import logging
import threading
from typing import Dict, List, Any, Optional

import requests

from lesson_pipeline.config import config

logger = logging.getLogger(__name__)

# Shape returned by whiteboard image pipeline per image entry
ImageEntry = Dict[str, Any]
# { prompt_text: [ImageEntry, ...] }
PipelineResult = Dict[str, List[ImageEntry]]


def call_whiteboard_pipeline(
    prompts: Dict[str, str],
    *,
    top_n_per_prompt: int = 2,
    model_id: str = "Qwen/Qwen3-VL-2B-Instruct",
    timeout: Optional[int] = None,
) -> PipelineResult:
    """
    POST to the whiteboard image-pipeline endpoint.

    Args:
        prompts: { prompt_text: subject } pairs to resolve
        top_n_per_prompt: how many images to return per prompt
        model_id: Qwen model to use for image selection
        timeout: HTTP timeout in seconds (defaults to config value)

    Returns:
        { prompt_text: [{ id, image_b64, image_mime, embedding, strokes }] }
        Returns {} on any error (caller must treat gracefully).
    """
    if not prompts:
        return {}

    url = config.whiteboard_pipeline_url
    effective_timeout = timeout or config.whiteboard_pipeline_timeout

    payload: Dict[str, Any] = {
        "prompts": prompts,
        "top_n_per_prompt": top_n_per_prompt,
        "model_id": model_id,
    }

    logger.info(
        f"[WhiteboardPipeline] Calling {url} with {len(prompts)} prompt(s): "
        f"{list(prompts.keys())}"
    )

    try:
        resp = requests.post(
            url,
            json=payload,
            timeout=effective_timeout,
            headers={"Content-Type": "application/json"},
        )
        resp.raise_for_status()
        body = resp.json()

        if not body.get("ok"):
            logger.warning(
                f"[WhiteboardPipeline] API returned ok=false: {body.get('error')}"
            )
            return {}

        result: PipelineResult = body.get("result") or {}
        summary = body.get("summary") or {}

        for prompt, entries in summary.items():
            for e in entries:
                logger.info(
                    f"[WhiteboardPipeline] {prompt!r} → id={e.get('id')} "
                    f"image={'✓' if e.get('has_image') else '✗'} "
                    f"embedding={'✓' if e.get('has_embedding') else '✗'} "
                    f"strokes={'✓' if e.get('has_strokes') else '✗'} "
                    f"({e.get('stroke_count', 0)} curves)"
                )

        return result

    except requests.Timeout:
        logger.error(
            f"[WhiteboardPipeline] Timed out after {effective_timeout}s "
            f"calling {url}"
        )
        return {}
    except requests.RequestException as exc:
        logger.error(f"[WhiteboardPipeline] HTTP error: {exc}")
        return {}
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        logger.error(f"[WhiteboardPipeline] Bad response: {exc}")
        return {}


class WhiteboardPipelinePrefetch:
    """
    Background prefetch of the whiteboard image pipeline.

    Usage::

        prefetch = WhiteboardPipelinePrefetch({"Cell membrane": "Biology"})
        # ... do other work (script generation) ...
        result = prefetch.get(timeout=600)   # blocks if not ready yet
    """

    def __init__(
        self,
        prompts: Dict[str, str],
        top_n_per_prompt: int = 2,
        model_id: str = "Qwen/Qwen3-VL-2B-Instruct",
    ) -> None:
        self._result: PipelineResult = {}
        self._event = threading.Event()
        self._thread = threading.Thread(
            target=self._run,
            args=(prompts, top_n_per_prompt, model_id),
            daemon=True,
            name="wb_pipeline_prefetch",
        )
        self._thread.start()

    def _run(
        self,
        prompts: Dict[str, str],
        top_n_per_prompt: int,
        model_id: str,
    ) -> None:
        try:
            self._result = call_whiteboard_pipeline(
                prompts,
                top_n_per_prompt=top_n_per_prompt,
                model_id=model_id,
            )
        except Exception as exc:
            logger.error(f"[WhiteboardPipeline] Prefetch thread crashed: {exc}")
            self._result = {}
        finally:
            self._event.set()

    def get(self, timeout: Optional[float] = None) -> PipelineResult:
        """Block until the prefetch is done (or timeout), then return the result."""
        self._event.wait(timeout=timeout)
        return self._result


def pick_best_entry_for_tag(
    tag_prompt: str,
    pipeline_result: PipelineResult,
) -> Optional[ImageEntry]:
    """
    Choose the best ImageEntry for a given tag prompt from a pipeline result.

    Strategy:
    1. Exact key match
    2. Case-insensitive substring match
    3. First available entry across all prompts (last resort)
    """
    if not pipeline_result:
        return None

    # 1) exact match
    entries = pipeline_result.get(tag_prompt)
    if entries:
        return entries[0]

    # 2) case-insensitive substring match
    tag_lower = tag_prompt.lower()
    for key, entries in pipeline_result.items():
        if entries and (tag_lower in key.lower() or key.lower() in tag_lower):
            return entries[0]

    # 3) fallback: first available
    for entries in pipeline_result.values():
        if entries:
            return entries[0]

    return None
