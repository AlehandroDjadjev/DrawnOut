"""
Unit tests for lesson_pipeline/pipelines/image_resolver.py

Tests the image tag resolution pipeline with mocked embeddings and Pinecone.
No real API calls are made.

Run with: python -m pytest lesson_pipeline/tests/test_image_resolver.py -v
"""
import unittest
from unittest.mock import patch, MagicMock
from typing import List

from lesson_pipeline.types import (
    ImageTag,
    ScriptImageRequest,
    ImageCandidate,
    ImageEmbeddingRecord,
    ResolvedImage,
)
from lesson_pipeline.pipelines.image_resolver import (
    resolve_image_tags_for_topic,
    resolve_to_resolved_images,
    resolve_single_tag,
    _extract_keywords,
    _keyword_score,
    _find_best_keyword_match,
    ResolutionStats,
)


# =============================================================================
# Test Fixtures
# =============================================================================

def make_mock_vector(dim: int = 1536) -> List[float]:
    """Create a mock embedding vector."""
    return [0.1] * dim


def make_mock_tags(count: int = 3) -> List[ImageTag]:
    """Create mock ImageTag objects."""
    return [
        ImageTag(
            id=f"tag_{i}",
            prompt=f"diagram of {['cell', 'atom', 'molecule'][i % 3]}",
            query=f"{['cell', 'atom', 'molecule'][i % 3]} structure",
        )
        for i in range(count)
    ]


def make_mock_script_requests(count: int = 2) -> List[ScriptImageRequest]:
    """Create mock ScriptImageRequest objects."""
    return [
        ScriptImageRequest(
            id=f"req_{i}",
            prompt=f"illustration of {['photosynthesis', 'mitosis'][i % 2]}",
        )
        for i in range(count)
    ]


def make_mock_pinecone_matches(count: int = 2) -> List[ImageEmbeddingRecord]:
    """Create mock Pinecone query results."""
    return [
        ImageEmbeddingRecord(
            id=f"vec_{i}",
            image_url=f"https://example.com/image_{i}.jpg",
            vector=[],  # Empty in query results
            topic_id="test_topic",
            original_prompt="test query",
            metadata={
                "title": f"Image {i}",
                "source": "wikimedia",
                "description": f"Test description {i}",
            }
        )
        for i in range(count)
    ]


def make_mock_candidates(count: int = 3) -> List[ImageCandidate]:
    """Create mock ImageCandidate objects for keyword fallback."""
    return [
        ImageCandidate(
            id=f"cand_{i}",
            source_url=f"https://fallback.com/image_{i}.jpg",
            title=["Cell Diagram", "Atom Structure", "Molecular Model"][i % 3],
            description=["A diagram of a cell", "Atomic structure illustration", "3D molecular model"][i % 3],
            tags=[["cell", "biology"], ["atom", "physics"], ["molecule", "chemistry"]][i % 3],
            source="test_source",
        )
        for i in range(count)
    ]


# =============================================================================
# Test Cases
# =============================================================================

class TestKeywordExtraction(unittest.TestCase):
    """Tests for keyword extraction helper."""
    
    def test_extracts_significant_words(self):
        """Should extract meaningful keywords, filtering stop words."""
        text = "a diagram of the cell membrane structure"
        keywords = _extract_keywords(text)
        
        self.assertIn("cell", keywords)
        self.assertIn("membrane", keywords)
        self.assertIn("structure", keywords)
        self.assertNotIn("the", keywords)
        self.assertNotIn("of", keywords)
    
    def test_filters_common_image_words(self):
        """Should filter out common image-related words."""
        text = "image showing the diagram of photosynthesis"
        keywords = _extract_keywords(text)
        
        self.assertIn("photosynthesis", keywords)
        self.assertNotIn("image", keywords)
        self.assertNotIn("showing", keywords)
        self.assertNotIn("diagram", keywords)
    
    def test_handles_empty_string(self):
        """Should return empty list for empty input."""
        self.assertEqual(_extract_keywords(""), [])


class TestKeywordScoring(unittest.TestCase):
    """Tests for keyword scoring of candidates."""
    
    def test_scores_matching_title(self):
        """Should score higher when keywords match title."""
        candidate = ImageCandidate(
            id="test",
            source_url="http://test.com/img.jpg",
            title="Cell Membrane Diagram",
        )
        
        score = _keyword_score(["cell", "membrane"], candidate)
        self.assertGreater(score, 0)
    
    def test_scores_matching_tags(self):
        """Should score when keywords match tags."""
        candidate = ImageCandidate(
            id="test",
            source_url="http://test.com/img.jpg",
            tags=["biology", "cell", "organism"],
        )
        
        score = _keyword_score(["cell", "biology"], candidate)
        self.assertEqual(score, 2)  # Both keywords match
    
    def test_zero_score_for_no_matches(self):
        """Should return 0 when no keywords match."""
        candidate = ImageCandidate(
            id="test",
            source_url="http://test.com/img.jpg",
            title="Quantum Physics",
            tags=["physics", "quantum"],
        )
        
        score = _keyword_score(["biology", "cell"], candidate)
        self.assertEqual(score, 0)


class TestFindBestKeywordMatch(unittest.TestCase):
    """Tests for keyword fallback matching."""
    
    def test_finds_best_match(self):
        """Should find candidate with most keyword matches."""
        candidates = [
            ImageCandidate(id="1", source_url="http://a.jpg", title="Physics Atom"),
            ImageCandidate(id="2", source_url="http://b.jpg", title="Cell Biology Diagram"),
            ImageCandidate(id="3", source_url="http://c.jpg", title="Chemistry"),
        ]
        
        match = _find_best_keyword_match("cell biology structure", candidates)
        
        self.assertIsNotNone(match)
        self.assertEqual(match.id, "2")  # Best match for "cell biology"
    
    def test_returns_none_for_no_matches(self):
        """Should return None when no candidates match."""
        candidates = [
            ImageCandidate(id="1", source_url="http://a.jpg", title="Quantum Physics"),
        ]
        
        match = _find_best_keyword_match("cell biology", candidates)
        self.assertIsNone(match)
    
    def test_returns_none_for_empty_candidates(self):
        """Should return None for empty candidates list."""
        match = _find_best_keyword_match("any query", [])
        self.assertIsNone(match)


class TestResolveImageTags(unittest.TestCase):
    """Tests for the main resolution pipeline."""
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_successful_vector_resolution(self, mock_embed, mock_query):
        """Should resolve tags via vector search."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = make_mock_pinecone_matches(2)
        
        tags = make_mock_tags(2)
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=tags,
        )
        
        self.assertEqual(len(results), 2)
        
        for result in results:
            self.assertIn("base_image_url", result)
            self.assertIn("vector_id", result)
            self.assertEqual(result["resolution_method"], "vector")
            self.assertFalse(result["needs_text_to_image"])
            self.assertTrue(result["base_image_url"].startswith("https://"))
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_keyword_fallback_when_no_vector_matches(self, mock_embed, mock_query):
        """Should fall back to keyword matching when Pinecone returns nothing."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = []  # No Pinecone matches
        
        tags = [ImageTag(id="tag_1", prompt="cell membrane structure")]
        fallback_candidates = [
            ImageCandidate(
                id="cand_1",
                source_url="https://fallback.com/cell.jpg",
                title="Cell Membrane Diagram",
                tags=["cell", "membrane"],
            )
        ]
        
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=tags,
            fallback_candidates=fallback_candidates,
        )
        
        self.assertEqual(len(results), 1)
        result = results[0]
        
        self.assertEqual(result["resolution_method"], "keyword")
        self.assertEqual(result["base_image_url"], "https://fallback.com/cell.jpg")
        self.assertFalse(result["needs_text_to_image"])
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_unresolved_when_no_matches(self, mock_embed, mock_query):
        """Should mark as needs_text_to_image when no matches found."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = []  # No matches
        
        tags = [ImageTag(id="tag_1", prompt="obscure topic")]
        
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=tags,
            fallback_candidates=None,  # No fallback
        )
        
        self.assertEqual(len(results), 1)
        result = results[0]
        
        self.assertTrue(result["needs_text_to_image"])
        self.assertEqual(result["base_image_url"], "")
        self.assertIsNone(result["resolution_method"])
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_handles_script_image_requests(self, mock_embed, mock_query):
        """Should handle ScriptImageRequest in addition to ImageTag."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = make_mock_pinecone_matches(1)
        
        requests = make_mock_script_requests(2)
        
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=requests,  # ScriptImageRequest list
        )
        
        self.assertEqual(len(results), 2)
        for result in results:
            self.assertIsNotNone(result["base_image_url"])
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_handles_embedding_exception(self, mock_embed, mock_query):
        """Should handle embedding errors gracefully."""
        mock_embed.side_effect = Exception("Embedding failed")
        
        tags = [ImageTag(id="tag_1", prompt="test")]
        
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=tags,
        )
        
        self.assertEqual(len(results), 1)
        result = results[0]
        
        self.assertTrue(result["needs_text_to_image"])
        self.assertIn("error", result)
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_handles_pinecone_exception(self, mock_embed, mock_query):
        """Should handle Pinecone query errors gracefully."""
        mock_embed.return_value = make_mock_vector()
        mock_query.side_effect = Exception("Pinecone error")
        
        tags = [ImageTag(id="tag_1", prompt="test")]
        
        results = resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=tags,
        )
        
        self.assertEqual(len(results), 1)
        self.assertTrue(results[0]["needs_text_to_image"])
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_uses_query_field_over_prompt(self, mock_embed, mock_query):
        """Should prefer tag.query over tag.prompt for embedding."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = make_mock_pinecone_matches(1)
        
        tag = ImageTag(
            id="tag_1",
            prompt="Show a cell diagram",  # Natural language
            query="cell structure diagram",  # Search optimized
        )
        
        resolve_image_tags_for_topic(
            topic_id="test_topic",
            tags=[tag],
        )
        
        # embed_text should be called with query, not prompt
        mock_embed.assert_called_once_with("cell structure diagram")


class TestResolveToResolvedImages(unittest.TestCase):
    """Tests for the typed ResolvedImage output."""
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_returns_resolved_image_objects(self, mock_embed, mock_query):
        """Should return proper ResolvedImage instances."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = make_mock_pinecone_matches(1)
        
        tags = [ImageTag(id="tag_1", prompt="cell diagram")]
        
        resolved = resolve_to_resolved_images(
            topic_id="test_topic",
            tags=tags,
        )
        
        self.assertEqual(len(resolved), 1)
        self.assertIsInstance(resolved[0], ResolvedImage)
        self.assertEqual(resolved[0].tag.id, "tag_1")
        self.assertTrue(resolved[0].base_image_url.startswith("https://"))
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_excludes_unresolved_tags(self, mock_embed, mock_query):
        """Should not include unresolved tags in ResolvedImage list."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = []  # No matches
        
        tags = [ImageTag(id="tag_1", prompt="test")]
        
        resolved = resolve_to_resolved_images(
            topic_id="test_topic",
            tags=tags,
        )
        
        self.assertEqual(len(resolved), 0)


class TestResolveSingleTag(unittest.TestCase):
    """Tests for single tag resolution."""
    
    @patch('lesson_pipeline.pipelines.image_resolver.query_images_by_text')
    @patch('lesson_pipeline.pipelines.image_resolver.embed_text')
    def test_resolves_single_tag(self, mock_embed, mock_query):
        """Should resolve a single tag."""
        mock_embed.return_value = make_mock_vector()
        mock_query.return_value = make_mock_pinecone_matches(1)
        
        tag = ImageTag(id="single", prompt="mitochondria")
        
        result = resolve_single_tag(
            tag=tag,
            topic_id="test_topic",
        )
        
        self.assertEqual(result["tag"].id, "single")
        self.assertFalse(result["needs_text_to_image"])


class TestResolutionStats(unittest.TestCase):
    """Tests for ResolutionStats dataclass."""
    
    def test_stats_to_dict(self):
        """Should serialize to dict correctly."""
        stats = ResolutionStats(
            total_tags=10,
            resolved_via_vector=7,
            resolved_via_keyword=2,
            unresolved=1,
        )
        
        d = stats.to_dict()
        
        self.assertEqual(d["total_tags"], 10)
        self.assertEqual(d["resolved_via_vector"], 7)
        self.assertEqual(d["resolved_via_keyword"], 2)
        self.assertEqual(d["unresolved"], 1)


if __name__ == "__main__":
    unittest.main()

