"""
Integration-style tests for lesson_pipeline/pipelines/orchestrator.py

Tests the full orchestration pipeline with mocked external services:
- ScriptWriterService (no OpenAI calls)
- ImageVectorSubprocess (no image research)
- Pinecone queries (no real vector DB)

Run with: python -m pytest lesson_pipeline/tests/test_orchestrator.py -v
"""
import unittest
from unittest.mock import patch, MagicMock, PropertyMock
from typing import List, Dict, Any

from lesson_pipeline.types import (
    UserPrompt,
    LessonDocument,
    ScriptOutput,
    ImageTag,
    ImageCandidate,
    ImageEmbeddingRecord,
    ResolvedImage,
)
from lesson_pipeline.pipelines.orchestrator import (
    generate_lesson,
    generate_lesson_json,
    generate_lesson_async_safe,
    OrchestrationStats,
    _wait_for_vector_subprocess,
    _fallback_index_info,
)


# =============================================================================
# Test Fixtures
# =============================================================================

def make_mock_script_output(prompt_id: str = "test_prompt") -> ScriptOutput:
    """Create a mock script with IMAGE tags."""
    content = """# Test Lesson

Today we'll learn about photosynthesis.

[IMAGE id="img_1" prompt="chloroplast diagram" query="chloroplast structure" style="diagram" aspect="16:9" time="8s" duration="6s"]

Chloroplasts are where photosynthesis happens.

[IMAGE id="img_2" prompt="light reactions illustration" query="photosynthesis light reaction" style="illustration" aspect="16:9" time="20s" duration="6s"]

The process converts sunlight into energy.
"""
    return ScriptOutput(
        prompt_id=prompt_id,
        content=content,
        image_requests=[],
    )


def make_mock_index_info(num_candidates: int = 3) -> Dict[str, Any]:
    """Create mock image indexing result."""
    candidates = [
        ImageCandidate(
            id=f"cand_{i}",
            source_url=f"https://example.com/image_{i}.jpg",
            title=f"Test Image {i}",
            description=f"Description {i}",
            source="wikimedia",
            tags=["biology", "photosynthesis"],
        )
        for i in range(num_candidates)
    ]
    
    return {
        "topic_id": "test_topic_123",
        "indexed_count": num_candidates,
        "candidates": candidates,
    }


def make_mock_pinecone_matches() -> List[ImageEmbeddingRecord]:
    """Create mock Pinecone query results."""
    return [
        ImageEmbeddingRecord(
            id="vec_1",
            image_url="https://example.com/matched_1.jpg",
            vector=[],
            topic_id="test_topic_123",
            original_prompt="chloroplast",
            metadata={"title": "Matched Image 1"},
        ),
    ]


def make_mock_vector() -> List[float]:
    """Create a mock 1536-dimensional embedding."""
    return [0.1] * 1536


# =============================================================================
# Test Cases
# =============================================================================

class TestOrchestrationStats(unittest.TestCase):
    """Tests for OrchestrationStats dataclass."""
    
    def test_stats_to_dict(self):
        """Should serialize stats correctly."""
        stats = OrchestrationStats(
            script_generated=True,
            script_length=500,
            image_tags_found=3,
            images_indexed=10,
            images_resolved=2,
            images_transformed=2,
            topic_id="test_123",
        )
        
        d = stats.to_dict()
        
        self.assertTrue(d["script_generated"])
        self.assertEqual(d["script_length"], 500)
        self.assertEqual(d["image_tags_found"], 3)
        self.assertEqual(d["topic_id"], "test_123")


class TestGenerateLesson(unittest.TestCase):
    """Integration tests for generate_lesson with mocked services."""
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_full_pipeline_success(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """Full pipeline should produce LessonDocument with images."""
        # Setup mocks
        mock_generate_script.return_value = make_mock_script_output()
        
        # Mock vector subprocess
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        # Mock resolver
        mock_resolve.return_value = [
            {
                "tag": ImageTag(id="img_1", prompt="chloroplast diagram"),
                "base_image_url": "https://example.com/matched.jpg",
                "base_metadata": {"title": "Matched"},
                "needs_text_to_image": False,
                "vector_id": "vec_1",
            },
            {
                "tag": ImageTag(id="img_2", prompt="light reactions"),
                "base_image_url": "https://example.com/matched2.jpg",
                "base_metadata": {"title": "Matched 2"},
                "needs_text_to_image": False,
                "vector_id": "vec_2",
            },
        ]
        
        # Run pipeline
        lesson = generate_lesson(
            prompt_text="Photosynthesis in plants",
            subject="Biology",
            duration_target=60.0,
        )
        
        # Verify result
        self.assertIsInstance(lesson, LessonDocument)
        self.assertIn("photosynthesis", lesson.content.lower()[:150])
        self.assertEqual(len(lesson.images), 2)
        self.assertEqual(lesson.indexed_image_count, 3)
        self.assertEqual(lesson.topic_id, "test_topic_123")
        
        # Verify content has injected images (placeholders replaced)
        self.assertNotIn("[[IMAGE:", lesson.content)
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_script_generation_failure(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """Should return error document when script generation fails."""
        mock_generate_script.side_effect = Exception("OpenAI error")
        
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        lesson = generate_lesson("Test topic")
        
        self.assertIsInstance(lesson, LessonDocument)
        self.assertIn("Failed", lesson.content)
        self.assertEqual(lesson.images, [])
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_continues_without_images_when_indexing_fails(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """Should continue with script even when image indexing fails."""
        mock_generate_script.return_value = make_mock_script_output()
        
        # Mock subprocess failure
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.side_effect = Exception("Pinecone error")
        mock_start_subprocess.return_value = mock_subprocess
        
        # Resolver returns no matches (no topic_id)
        mock_resolve.return_value = [
            {
                "tag": ImageTag(id="img_1", prompt="test"),
                "base_image_url": "",
                "base_metadata": None,
                "needs_text_to_image": True,
                "vector_id": None,
            },
        ]
        
        lesson = generate_lesson("Test topic")
        
        # Should still have content
        self.assertIsInstance(lesson, LessonDocument)
        self.assertIn("learn", lesson.content.lower())
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_no_image_tags_in_script(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """Should handle scripts with no IMAGE tags gracefully."""
        # Script without IMAGE tags
        mock_generate_script.return_value = ScriptOutput(
            prompt_id="test",
            content="# Lesson\n\nJust text, no images.",
            image_requests=[],
        )
        
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        lesson = generate_lesson("Test topic")
        
        self.assertEqual(lesson.images, [])
        self.assertIn("Just text", lesson.content)
        
        # Resolver should not be called
        mock_resolve.assert_not_called()
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_resolver_gets_fallback_candidates(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """Should pass indexed candidates to resolver for keyword fallback."""
        mock_generate_script.return_value = make_mock_script_output()
        
        candidates = make_mock_index_info()["candidates"]
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        mock_resolve.return_value = []
        
        generate_lesson("Test")
        
        # Check that resolver was called with fallback_candidates
        call_kwargs = mock_resolve.call_args[1]
        self.assertIn("fallback_candidates", call_kwargs)
        self.assertEqual(len(call_kwargs["fallback_candidates"]), len(candidates))


class TestGenerateLessonJson(unittest.TestCase):
    """Tests for JSON serialization of lesson output."""
    
    @patch('lesson_pipeline.pipelines.orchestrator.generate_lesson')
    def test_returns_dict(self, mock_generate):
        """Should return JSON-serializable dict."""
        mock_generate.return_value = LessonDocument(
            prompt_id="test",
            content="Test content",
            images=[],
            topic_id="topic_123",
            indexed_image_count=5,
        )
        
        result = generate_lesson_json("Test topic")
        
        self.assertIsInstance(result, dict)
        self.assertIn("id", result)
        self.assertIn("content", result)
        self.assertIn("images", result)
        self.assertIn("topic_id", result)


class TestGenerateLessonAsyncSafe(unittest.TestCase):
    """Tests for API-safe wrapper."""
    
    @patch('lesson_pipeline.pipelines.orchestrator.generate_lesson_json')
    def test_success_response(self, mock_generate_json):
        """Should wrap successful result in success envelope."""
        mock_generate_json.return_value = {"content": "test", "images": []}
        
        result = generate_lesson_async_safe("Test")
        
        self.assertTrue(result["success"])
        self.assertIn("data", result)
        self.assertNotIn("error", result)
    
    @patch('lesson_pipeline.pipelines.orchestrator.generate_lesson_json')
    def test_error_response(self, mock_generate_json):
        """Should wrap errors gracefully."""
        mock_generate_json.side_effect = Exception("Something broke")
        
        result = generate_lesson_async_safe("Test")
        
        self.assertFalse(result["success"])
        self.assertIn("error", result)
        self.assertIn("data", result)  # Still has fallback data


class TestVectorSubprocessWaiting(unittest.TestCase):
    """Tests for subprocess timeout handling."""
    
    def test_timeout_returns_fallback(self):
        """Should return fallback when subprocess times out."""
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.side_effect = TimeoutError("Timed out")
        
        result = _wait_for_vector_subprocess(mock_subprocess, timeout=1.0)
        
        self.assertEqual(result["topic_id"], "")
        self.assertEqual(result["indexed_count"], 0)
        self.assertEqual(result["candidates"], [])
    
    def test_success_returns_result(self):
        """Should return actual result on success."""
        expected = make_mock_index_info()
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = expected
        
        result = _wait_for_vector_subprocess(mock_subprocess, timeout=10.0)
        
        self.assertEqual(result["topic_id"], expected["topic_id"])
        self.assertEqual(result["indexed_count"], expected["indexed_count"])


class TestFallbackIndexInfo(unittest.TestCase):
    """Tests for fallback payload."""
    
    def test_fallback_structure(self):
        """Fallback should have correct structure."""
        fallback = _fallback_index_info()
        
        self.assertIn("topic_id", fallback)
        self.assertIn("indexed_count", fallback)
        self.assertIn("candidates", fallback)
        self.assertEqual(fallback["indexed_count"], 0)


class TestAPIResponseContract(unittest.TestCase):
    """Tests to verify API response contract is consistent."""
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_response_has_required_fields(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """API response should have all required fields."""
        mock_generate_script.return_value = make_mock_script_output()
        
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        mock_resolve.return_value = []
        
        result = generate_lesson_json("Test")
        
        # Required fields per API contract
        required_fields = [
            "id",
            "prompt_id",
            "content",
            "images",
            "topic_id",
            "indexed_image_count",
            "image_slots",
        ]
        
        for field in required_fields:
            self.assertIn(field, result, f"Missing required field: {field}")
    
    @patch('lesson_pipeline.pipelines.orchestrator.resolve_image_tags_for_topic')
    @patch('lesson_pipeline.pipelines.orchestrator.start_image_vector_subprocess')
    @patch('lesson_pipeline.pipelines.orchestrator.generate_script')
    def test_image_slots_present(
        self,
        mock_generate_script,
        mock_start_subprocess,
        mock_resolve,
    ):
        """image_slots should be present in response."""
        mock_generate_script.return_value = make_mock_script_output()
        
        mock_subprocess = MagicMock()
        mock_subprocess.wait_for_result.return_value = make_mock_index_info()
        mock_start_subprocess.return_value = mock_subprocess
        
        mock_resolve.return_value = [
            {
                "tag": ImageTag(id="img_1", prompt="test", time_offset=8.0, duration=6.0),
                "base_image_url": "https://example.com/test.jpg",
                "base_metadata": {},
                "needs_text_to_image": False,
                "vector_id": "v1",
            },
        ]
        
        result = generate_lesson_json("Test")
        
        self.assertIn("image_slots", result)
        self.assertIsInstance(result["image_slots"], list)
        
        # Should have slots for the IMAGE tags
        self.assertGreater(len(result["image_slots"]), 0)


if __name__ == "__main__":
    unittest.main()
