"""
Background subprocess for researching images and indexing them in Pinecone.

Runs alongside script generation so downstream steps can query topic IDs,
candidate metadata, and indexing statistics without blocking the main
lesson orchestration thread.
"""
from concurrent.futures import Future, ThreadPoolExecutor
import logging
from typing import Any, Dict, Optional

from lesson_pipeline.pipelines.image_ingestion import run_image_research_and_index_sync
from lesson_pipeline.types import UserPrompt

logger = logging.getLogger(__name__)

# Module-level executor so multiple lesson requests can share the same pool.
_EXECUTOR = ThreadPoolExecutor(max_workers=4)


class ImageVectorSubprocess:
    """
    Wrapper that schedules image research + vector indexing work in the background.

    Usage:
        subprocess = ImageVectorSubprocess(prompt, subject)
        subprocess.start()
        ...
        image_index_info = subprocess.wait_for_result()
    """

    def __init__(
        self,
        prompt: UserPrompt,
        subject: str = "General",
        max_images: Optional[int] = None,
    ):
        self.prompt = prompt
        self.subject = subject
        self.max_images = max_images
        self._future: Optional[Future] = None
        self._result: Optional[Dict[str, Any]] = None
        self.status: str = "pending"  # pending | running | completed | failed

    def start(self) -> Future:
        """Kick off the background ingestion run (idempotent)."""
        if self._future is not None:
            return self._future

        def _task():
            self.status = "running"
            logger.info("ImageVectorSubprocess started for prompt=%s", self.prompt.text)
            try:
                return run_image_research_and_index_sync(
                    prompt=self.prompt,
                    subject=self.subject,
                    max_images=self.max_images,
                )
            except Exception as exc:  # pragma: no cover - logged for observability
                logger.error("Image vector subprocess failed: %s", exc)
                raise

        self._future = _EXECUTOR.submit(_task)
        return self._future

    def cancel(self) -> bool:
        """Attempt to cancel the background work."""
        if self._future is None:
            return False
        cancelled = self._future.cancel()
        if cancelled:
            self.status = "cancelled"
        return cancelled

    def result_ready(self) -> bool:
        """Return True if the background work already completed."""
        if self._result is not None:
            return True
        if self._future is None:
            return False
        return self._future.done()

    def peek_result(self) -> Optional[Dict[str, Any]]:
        """
        Return the result if ready without blocking, otherwise None.
        Always caches the payload once available.
        """
        if self._result is not None:
            return self._result
        if not self.result_ready() or self._future is None:
            return None
        try:
            self._result = self._future.result()
            self.status = "completed"
        except Exception as exc:
            logger.error("Image vector subprocess raised during peek: %s", exc)
            self.status = "failed"
            self._result = self._fallback_payload()
        return self._result

    def wait_for_result(self, timeout: Optional[float] = None) -> Dict[str, Any]:
        """
        Block until the background job finishes (or timeout) and return payload.

        Guarantees a dict structure even if the run fails.
        """
        if self._result is not None:
            return self._result

        if self._future is None:
            self.start()

        try:
            self._result = self._future.result(timeout=timeout)
            self.status = "completed"
        except Exception as exc:
            logger.error("Image vector subprocess failed: %s", exc)
            self.status = "failed"
            self._result = self._fallback_payload()

        if not self._result:
            self._result = self._fallback_payload()

        return self._result

    def _fallback_payload(self) -> Dict[str, Any]:
        return {
            "topic_id": "",
            "indexed_count": 0,
            "candidates": [],
        }


def start_image_vector_subprocess(
    prompt: UserPrompt,
    subject: str = "General",
    max_images: Optional[int] = None,
) -> ImageVectorSubprocess:
    """Convenience factory."""
    subprocess = ImageVectorSubprocess(prompt, subject, max_images)
    subprocess.start()
    return subprocess




