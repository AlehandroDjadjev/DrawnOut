"""
Unit tests for lesson_pipeline/pipelines/image_ingestion.py

These tests mock all external dependencies to run fast without:
- Network calls to image research APIs
- Loading the SigLIP2 model
- Connecting to Pinecone

Run with: python -m pytest lesson_pipeline/tests/test_image_ingestion.py -v
"""
import unittest
from unittest.mock import patch, MagicMock, call
from typing import List

from lesson_pipeline.types import UserPrompt, ImageCandidate, ImageEmbeddingRecord
from lesson_pipeline.pipelines.image_ingestion import (
    run_image_research_and_index_sync,
    ingest_candidates,
    _generate_topic_id,
    _build_metadata,
    _create_embedding_records,
    IngestionStats,
)


# =============================================================================
# Test Fixtures
# =============================================================================

def make_mock_candidates(count: int = 3) -> List[ImageCandidate]:
    """Create mock ImageCandidate objects for testing."""
    candidates = []
    for i in range(count):
        candidates.append(ImageCandidate(
            id=f"img_{i}",
            source_url=f"https://example.com/image_{i}.jpg",
            title=f"Test Image {i}",
            description=f"Description for image {i}",
            source="test_source",
            tags=["test", "mock"],
            license="CC-BY",
            width=800,
            height=600,
            metadata={"extra_key": f"value_{i}"}
        ))
    return candidates


def make_mock_vectors(count: int) -> List[List[float]]:
    """Create mock embedding vectors (1536-dimensional)."""
    return [[float(i) / 1536 for _ in range(1536)] for i in range(count)]


# =============================================================================
# Test Cases
# =============================================================================

class TestHelperFunctions(unittest.TestCase):
    """Tests for helper functions."""
    
    def test_generate_topic_id_is_deterministic(self):
        """Same prompt should generate same topic ID."""
        prompt1 = "photosynthesis in plants"
        prompt2 = "photosynthesis in plants"
        
        id1 = _generate_topic_id(prompt1)
        id2 = _generate_topic_id(prompt2)
        
        self.assertEqual(id1, id2)
    
    def test_generate_topic_id_differs_for_different_prompts(self):
        """Different prompts should generate different topic IDs."""
        id1 = _generate_topic_id("photosynthesis")
        id2 = _generate_topic_id("cell division")
        
        self.assertNotEqual(id1, id2)
    
    def test_build_metadata_filters_none_values(self):
        """Metadata should not contain None values."""
        candidate = ImageCandidate(
            id="test",
            source_url="http://example.com/img.jpg",
            title="Test",
            description=None,  # None value
            width=None,  # None value
            height=600,
        )
        
        metadata = _build_metadata(candidate, "Biology", "test query")
        
        self.assertNotIn("description", metadata)
        self.assertNotIn("width", metadata)
        self.assertEqual(metadata["height"], 600)
        self.assertEqual(metadata["title"], "Test")
    
    def test_build_metadata_includes_subject_and_query(self):
        """Metadata should include subject and query."""
        candidate = ImageCandidate(
            id="test",
            source_url="http://example.com/img.jpg",
        )
        
        metadata = _build_metadata(candidate, "Physics", "quantum mechanics")
        
        self.assertEqual(metadata["subject"], "Physics")
        self.assertEqual(metadata["query"], "quantum mechanics")
    
    def test_create_embedding_records_correct_mapping(self):
        """Records should be created with correct vector-to-candidate mapping."""
        candidates = make_mock_candidates(5)
        # Only indices 0, 2, 4 succeeded
        vectors = make_mock_vectors(3)
        success_indices = [0, 2, 4]
        
        records = _create_embedding_records(
            candidates=candidates,
            vectors=vectors,
            success_indices=success_indices,
            topic_id="test_topic",
            prompt_text="test prompt",
            subject="Test",
        )
        
        self.assertEqual(len(records), 3)
        
        # Check mapping is correct
        self.assertEqual(records[0].id, "img_0")  # candidates[0]
        self.assertEqual(records[1].id, "img_2")  # candidates[2]
        self.assertEqual(records[2].id, "img_4")  # candidates[4]
        
        # Check vectors are assigned correctly
        self.assertEqual(records[0].vector, vectors[0])
        self.assertEqual(records[1].vector, vectors[1])
        self.assertEqual(records[2].vector, vectors[2])


class TestIngestionStats(unittest.TestCase):
    """Tests for IngestionStats dataclass."""
    
    def test_stats_default_values(self):
        """Stats should have sensible defaults."""
        stats = IngestionStats(topic_id="test")
        
        self.assertEqual(stats.candidates_found, 0)
        self.assertEqual(stats.embedding_failures, 0)
        self.assertEqual(stats.errors, [])
    
    def test_stats_to_dict(self):
        """Stats should serialize to dict correctly."""
        stats = IngestionStats(
            topic_id="test",
            candidates_found=10,
            embedding_successes=8,
            embedding_failures=2,
        )
        
        d = stats.to_dict()
        
        self.assertEqual(d["topic_id"], "test")
        self.assertEqual(d["candidates_found"], 10)
        self.assertEqual(d["embedding_successes"], 8)


class TestImageIngestionPipeline(unittest.TestCase):
    """Tests for the main ingestion pipeline."""
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_successful_full_pipeline(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Full pipeline should work end-to-end with mocks."""
        # Setup mocks
        candidates = make_mock_candidates(3)
        vectors = make_mock_vectors(3)
        
        mock_research.return_value = candidates
        mock_embed.return_value = (vectors, [0, 1, 2])
        mock_upsert.return_value = None
        
        # Run pipeline
        prompt = UserPrompt(text="photosynthesis diagram")
        result = run_image_research_and_index_sync(prompt, subject="Biology")
        
        # Verify result structure
        self.assertIn("topic_id", result)
        self.assertIn("indexed_count", result)
        self.assertIn("candidates", result)
        self.assertIn("stats", result)
        
        # Verify counts
        self.assertEqual(result["indexed_count"], 3)
        self.assertEqual(len(result["candidates"]), 3)
        
        # Verify stats
        stats = result["stats"]
        self.assertEqual(stats["candidates_found"], 3)
        self.assertEqual(stats["embedding_successes"], 3)
        self.assertEqual(stats["embedding_failures"], 0)
        self.assertEqual(stats["upserted_count"], 3)
        
        # Verify mocks called correctly
        mock_research.assert_called_once()
        mock_embed.assert_called_once()
        mock_upsert.assert_called_once()
        
        # Verify upsert received correct records
        upserted_records = mock_upsert.call_args[0][0]
        self.assertEqual(len(upserted_records), 3)
        self.assertIsInstance(upserted_records[0], ImageEmbeddingRecord)
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_partial_embedding_success(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Pipeline should handle partial embedding failures gracefully."""
        candidates = make_mock_candidates(5)
        # Only 3 out of 5 succeeded
        vectors = make_mock_vectors(3)
        success_indices = [0, 2, 4]
        
        mock_research.return_value = candidates
        mock_embed.return_value = (vectors, success_indices)
        mock_upsert.return_value = None
        
        prompt = UserPrompt(text="test query")
        result = run_image_research_and_index_sync(prompt)
        
        # Should only upsert the 3 successful ones
        self.assertEqual(result["indexed_count"], 3)
        
        stats = result["stats"]
        self.assertEqual(stats["candidates_found"], 5)
        self.assertEqual(stats["embedding_attempts"], 5)
        self.assertEqual(stats["embedding_successes"], 3)
        self.assertEqual(stats["embedding_failures"], 2)
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_no_candidates_found(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Pipeline should handle no candidates found."""
        mock_research.return_value = []
        
        prompt = UserPrompt(text="obscure topic")
        result = run_image_research_and_index_sync(prompt)
        
        self.assertEqual(result["indexed_count"], 0)
        self.assertEqual(result["candidates"], [])
        
        # Embed and upsert should not be called
        mock_embed.assert_not_called()
        mock_upsert.assert_not_called()
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_all_embeddings_fail(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Pipeline should handle all embeddings failing."""
        candidates = make_mock_candidates(3)
        
        mock_research.return_value = candidates
        mock_embed.return_value = ([], [])  # All failed
        
        prompt = UserPrompt(text="test")
        result = run_image_research_and_index_sync(prompt)
        
        self.assertEqual(result["indexed_count"], 0)
        stats = result["stats"]
        self.assertEqual(stats["embedding_successes"], 0)
        self.assertEqual(stats["embedding_failures"], 3)
        
        # Upsert should not be called with empty records
        mock_upsert.assert_not_called()
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_research_exception_handled(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Research exceptions should be caught and logged."""
        mock_research.side_effect = Exception("API error")
        
        prompt = UserPrompt(text="test")
        result = run_image_research_and_index_sync(prompt)
        
        # Should not crash, return graceful failure
        self.assertEqual(result["indexed_count"], 0)
        self.assertIn("Research phase failed", result["stats"]["errors"][0])
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_embedding_exception_handled(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Embedding exceptions should be caught and logged."""
        mock_research.return_value = make_mock_candidates(3)
        mock_embed.side_effect = Exception("Model error")
        
        prompt = UserPrompt(text="test")
        result = run_image_research_and_index_sync(prompt)
        
        self.assertEqual(result["indexed_count"], 0)
        self.assertIn("Embedding phase failed", result["stats"]["errors"][0])
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_upsert_exception_handled(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Upsert exceptions should be caught and logged."""
        mock_research.return_value = make_mock_candidates(3)
        mock_embed.return_value = (make_mock_vectors(3), [0, 1, 2])
        mock_upsert.side_effect = Exception("Pinecone error")
        
        prompt = UserPrompt(text="test")
        result = run_image_research_and_index_sync(prompt)
        
        self.assertEqual(result["indexed_count"], 0)
        self.assertIn("Pinecone upsert failed", result["stats"]["errors"][0])
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_record_metadata_correct(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Upserted records should have correct metadata."""
        candidates = [ImageCandidate(
            id="test_id",
            source_url="https://example.com/test.jpg",
            title="Test Title",
            description="Test Description",
            source="wikimedia",
            license="CC-BY-SA",
            width=1024,
            height=768,
            tags=["biology", "cell"],
            metadata={"custom_field": "custom_value"}
        )]
        
        mock_research.return_value = candidates
        mock_embed.return_value = (make_mock_vectors(1), [0])
        
        prompt = UserPrompt(text="cell diagram")
        run_image_research_and_index_sync(prompt, subject="Biology")
        
        # Check the record passed to upsert
        upserted_records = mock_upsert.call_args[0][0]
        record = upserted_records[0]
        
        self.assertEqual(record.id, "test_id")
        self.assertEqual(record.image_url, "https://example.com/test.jpg")
        self.assertEqual(record.original_prompt, "cell diagram")
        self.assertIn("title", record.metadata)
        self.assertEqual(record.metadata["title"], "Test Title")
        self.assertEqual(record.metadata["subject"], "Biology")
        self.assertEqual(record.metadata["custom_field"], "custom_value")


class TestIngestCandidates(unittest.TestCase):
    """Tests for the ingest_candidates function (skip research step)."""
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    def test_direct_ingest_success(self, mock_embed, mock_upsert):
        """Direct ingestion should work with pre-researched candidates."""
        candidates = make_mock_candidates(3)
        vectors = make_mock_vectors(3)
        
        mock_embed.return_value = (vectors, [0, 1, 2])
        
        result = ingest_candidates(
            candidates=candidates,
            topic_id="custom_topic",
            prompt_text="custom prompt",
            subject="Chemistry"
        )
        
        self.assertEqual(result["indexed_count"], 3)
        self.assertEqual(result["topic_id"], "custom_topic")
        
        # Verify upsert was called
        mock_upsert.assert_called_once()
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    def test_direct_ingest_empty_candidates(self, mock_embed, mock_upsert):
        """Empty candidates list should return early."""
        result = ingest_candidates(
            candidates=[],
            topic_id="test",
            prompt_text="test"
        )
        
        self.assertEqual(result["indexed_count"], 0)
        mock_embed.assert_not_called()
        mock_upsert.assert_not_called()


class TestVectorShapes(unittest.TestCase):
    """Tests to verify vector shapes match Pinecone requirements."""
    
    @patch('lesson_pipeline.pipelines.image_ingestion.upsert_images')
    @patch('lesson_pipeline.pipelines.image_ingestion.embed_images_batch')
    @patch('lesson_pipeline.pipelines.image_ingestion.research_images')
    def test_vectors_are_1536_dimensional(
        self,
        mock_research,
        mock_embed,
        mock_upsert
    ):
        """Each vector should be exactly 1536 dimensions."""
        candidates = make_mock_candidates(2)
        vectors = [[0.1] * 1536, [0.2] * 1536]  # Exactly 1536 dims
        
        mock_research.return_value = candidates
        mock_embed.return_value = (vectors, [0, 1])
        
        prompt = UserPrompt(text="test")
        run_image_research_and_index_sync(prompt)
        
        # Check vectors in upserted records
        upserted_records = mock_upsert.call_args[0][0]
        for record in upserted_records:
            self.assertEqual(len(record.vector), 1536)
            self.assertTrue(all(isinstance(v, float) for v in record.vector))


if __name__ == "__main__":
    unittest.main()

