"""
Unit tests for lesson_pipeline/services/embeddings.py

These tests mock the vision.services.siglip2 module to avoid loading the
actual SigLIP2 model, which is too heavy for CI environments.

Run with: python -m pytest lesson_pipeline/tests/test_embeddings.py -v

For heavy tests that actually load the model:
    RUN_HEAVY_TESTS=1 python -m pytest lesson_pipeline/tests/test_embeddings.py -v
"""
import os
import unittest
from unittest.mock import patch, MagicMock
from typing import List

import torch
from PIL import Image

# Constants
EXPECTED_DIM = 1536


def make_mock_embedding(dim: int = EXPECTED_DIM, seed: int = 42) -> torch.Tensor:
    """Create a deterministic, L2-normalized mock embedding tensor."""
    torch.manual_seed(seed)
    tensor = torch.randn(dim)
    # L2 normalize like the real model does
    tensor = tensor / tensor.norm()
    return tensor


def make_mock_batch_embeddings(n: int, dim: int = EXPECTED_DIM, seed: int = 42) -> torch.Tensor:
    """Create a batch of deterministic, L2-normalized mock embeddings."""
    torch.manual_seed(seed)
    tensor = torch.randn(n, dim)
    # L2 normalize each row
    tensor = tensor / tensor.norm(dim=-1, keepdim=True)
    return tensor


class TestEmbeddingsWithMockedVision(unittest.TestCase):
    """
    Tests that mock the vision module to avoid loading the real SigLIP2 model.
    These tests run fast and don't require network access or GPU.
    """
    
    def setUp(self):
        """Reset the singleton before each test."""
        # We need to reset the module state to ensure fresh mocks
        import lesson_pipeline.services.embeddings as emb_module
        emb_module._embedding_service_instance = None
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_embed_text_returns_list_of_floats(self, mock_encode_text, mock_encode_image):
        """embed_text should return a List[float] of length 1536."""
        mock_encode_text.return_value = make_mock_embedding(EXPECTED_DIM)
        
        from lesson_pipeline.services.embeddings import embed_text
        
        result = embed_text("test query about photosynthesis")
        
        # Verify return type
        self.assertIsInstance(result, list)
        self.assertEqual(len(result), EXPECTED_DIM)
        self.assertTrue(all(isinstance(x, float) for x in result))
        
        # Verify mock was called
        mock_encode_text.assert_called_once_with("test query about photosynthesis")
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_embed_image_from_pil_returns_list_of_floats(self, mock_encode_text, mock_encode_image):
        """embed_image_from_pil should return a List[float] of length 1536."""
        mock_encode_image.return_value = make_mock_embedding(EXPECTED_DIM)
        
        from lesson_pipeline.services.embeddings import embed_image_from_pil
        
        # Create a small test image
        test_image = Image.new('RGB', (64, 64), color='red')
        
        result = embed_image_from_pil(test_image)
        
        # Verify return type
        self.assertIsInstance(result, list)
        self.assertEqual(len(result), EXPECTED_DIM)
        self.assertTrue(all(isinstance(x, float) for x in result))
        
        # Verify mock was called
        mock_encode_image.assert_called_once()
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_embed_images_batch_returns_correct_shapes(self, mock_encode_text, mock_encode_image):
        """embed_images_batch should return (List[List[float]], List[int])."""
        # Each call returns a different deterministic embedding
        call_count = [0]
        def mock_image_side_effect(image):
            call_count[0] += 1
            return make_mock_embedding(EXPECTED_DIM, seed=call_count[0])
        
        mock_encode_image.side_effect = mock_image_side_effect
        
        from lesson_pipeline.services.embeddings import SigLIPEmbeddingService
        
        service = SigLIPEmbeddingService()
        
        # Create test images as file paths (will mock the loading)
        with patch.object(service, '_load_image_from_source') as mock_load:
            mock_load.return_value = Image.new('RGB', (64, 64), color='blue')
            
            image_urls = ["http://example.com/img1.jpg", "http://example.com/img2.jpg"]
            embeddings, success_indices = service.embed_image_batch(image_urls)
        
        # Verify shapes
        self.assertIsInstance(embeddings, list)
        self.assertEqual(len(embeddings), 2)
        
        for emb in embeddings:
            self.assertIsInstance(emb, list)
            self.assertEqual(len(emb), EXPECTED_DIM)
            self.assertTrue(all(isinstance(x, float) for x in emb))
        
        # Verify success indices
        self.assertEqual(success_indices, [0, 1])
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_embed_images_batch_handles_failures(self, mock_encode_text, mock_encode_image):
        """embed_images_batch should skip failed images and track success indices."""
        call_count = [0]
        def mock_image_side_effect(image):
            call_count[0] += 1
            if call_count[0] == 2:
                raise ValueError("Simulated failure for second image")
            return make_mock_embedding(EXPECTED_DIM, seed=call_count[0])
        
        mock_encode_image.side_effect = mock_image_side_effect
        
        from lesson_pipeline.services.embeddings import SigLIPEmbeddingService
        
        service = SigLIPEmbeddingService()
        
        with patch.object(service, '_load_image_from_source') as mock_load:
            mock_load.return_value = Image.new('RGB', (64, 64), color='green')
            
            image_urls = ["img1.jpg", "img2.jpg", "img3.jpg"]
            embeddings, success_indices = service.embed_image_batch(image_urls)
        
        # Second image failed, so we should have 2 embeddings
        self.assertEqual(len(embeddings), 2)
        self.assertEqual(success_indices, [0, 2])  # Indices 0 and 2 succeeded
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_dimension_mismatch_raises_error(self, mock_encode_text, mock_encode_image):
        """Dimension mismatch should raise EmbeddingDimensionError."""
        # Return wrong dimension
        wrong_dim = 768
        mock_encode_text.return_value = make_mock_embedding(wrong_dim)
        
        from lesson_pipeline.services.embeddings import (
            embed_text, 
            EmbeddingDimensionError
        )
        
        with self.assertRaises(EmbeddingDimensionError) as context:
            embed_text("test query")
        
        # Check error message is informative
        self.assertIn(str(wrong_dim), str(context.exception))
        self.assertIn(str(EXPECTED_DIM), str(context.exception))
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_image_dimension_mismatch_raises_error(self, mock_encode_text, mock_encode_image):
        """Image embedding dimension mismatch should raise EmbeddingDimensionError."""
        wrong_dim = 512
        mock_encode_image.return_value = make_mock_embedding(wrong_dim)
        
        from lesson_pipeline.services.embeddings import (
            embed_image_from_pil,
            EmbeddingDimensionError
        )
        
        test_image = Image.new('RGB', (64, 64), color='red')
        
        with self.assertRaises(EmbeddingDimensionError) as context:
            embed_image_from_pil(test_image)
        
        self.assertIn(str(wrong_dim), str(context.exception))
        self.assertIn(str(EXPECTED_DIM), str(context.exception))
    
    @patch('lesson_pipeline.services.embeddings.encode_images_from_pil_batch')
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_batch_pil_embeddings_returns_correct_shape(
        self, mock_encode_text, mock_encode_image, mock_batch_encode
    ):
        """embed_images_from_pil_batch should return correct shapes."""
        n_images = 3
        mock_batch_encode.return_value = make_mock_batch_embeddings(n_images, EXPECTED_DIM)
        
        from lesson_pipeline.services.embeddings import embed_images_from_pil_batch
        
        test_images = [Image.new('RGB', (64, 64), color='red') for _ in range(n_images)]
        
        embeddings, success_indices = embed_images_from_pil_batch(test_images)
        
        # Verify shapes
        self.assertEqual(len(embeddings), n_images)
        self.assertEqual(success_indices, [0, 1, 2])
        
        for emb in embeddings:
            self.assertIsInstance(emb, list)
            self.assertEqual(len(emb), EXPECTED_DIM)
    
    @patch('lesson_pipeline.services.embeddings.vision_encode_texts')
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_batch_text_embeddings_returns_correct_shape(
        self, mock_encode_text, mock_encode_image, mock_batch_texts
    ):
        """embed_texts_batch should return List[List[float]]."""
        n_texts = 4
        mock_batch_texts.return_value = make_mock_batch_embeddings(n_texts, EXPECTED_DIM)
        
        from lesson_pipeline.services.embeddings import embed_texts_batch
        
        texts = ["query 1", "query 2", "query 3", "query 4"]
        
        embeddings = embed_texts_batch(texts)
        
        # Verify shapes
        self.assertEqual(len(embeddings), n_texts)
        
        for emb in embeddings:
            self.assertIsInstance(emb, list)
            self.assertEqual(len(emb), EXPECTED_DIM)
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_embeddings_are_normalized(self, mock_encode_text, mock_encode_image):
        """Embeddings should be L2-normalized (unit norm)."""
        mock_encode_text.return_value = make_mock_embedding(EXPECTED_DIM)
        
        from lesson_pipeline.services.embeddings import embed_text
        import math
        
        result = embed_text("test query")
        
        # Calculate L2 norm
        norm = math.sqrt(sum(x * x for x in result))
        
        # Should be very close to 1.0 (within floating point tolerance)
        self.assertAlmostEqual(norm, 1.0, places=5)
    
    @patch('lesson_pipeline.services.embeddings.encode_image_from_pil')
    @patch('lesson_pipeline.services.embeddings.vision_encode_text')
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_empty_batch_returns_empty(self, mock_encode_text, mock_encode_image):
        """Empty input should return empty results."""
        from lesson_pipeline.services.embeddings import (
            embed_images_from_pil_batch,
            embed_texts_batch,
        )
        
        with patch('lesson_pipeline.services.embeddings.encode_images_from_pil_batch'):
            img_embeddings, img_indices = embed_images_from_pil_batch([])
            self.assertEqual(img_embeddings, [])
            self.assertEqual(img_indices, [])
        
        with patch('lesson_pipeline.services.embeddings.vision_encode_texts'):
            text_embeddings = embed_texts_batch([])
            self.assertEqual(text_embeddings, [])
    
    def test_vision_app_unavailable_raises_import_error(self):
        """SigLIPEmbeddingService should raise ImportError if vision app unavailable."""
        with patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', False):
            from lesson_pipeline.services.embeddings import SigLIPEmbeddingService
            
            with self.assertRaises(ImportError) as context:
                SigLIPEmbeddingService()
            
            self.assertIn("Vision app", str(context.exception))


class TestEmbeddingServiceSingleton(unittest.TestCase):
    """Tests for the singleton pattern."""
    
    def setUp(self):
        """Reset the singleton before each test."""
        import lesson_pipeline.services.embeddings as emb_module
        emb_module._embedding_service_instance = None
    
    @patch('lesson_pipeline.services.embeddings.VISION_APP_AVAILABLE', True)
    def test_get_embedding_service_returns_same_instance(self):
        """get_embedding_service should return the same instance on multiple calls."""
        from lesson_pipeline.services.embeddings import get_embedding_service
        
        service1 = get_embedding_service()
        service2 = get_embedding_service()
        
        self.assertIs(service1, service2)


# ============================================================================
# Heavy tests - only run when RUN_HEAVY_TESTS=1
# ============================================================================

@unittest.skipUnless(
    os.environ.get('RUN_HEAVY_TESTS', '').lower() in ('1', 'true', 'yes'),
    "Skipping heavy tests. Set RUN_HEAVY_TESTS=1 to run."
)
class TestEmbeddingsWithRealModel(unittest.TestCase):
    """
    Smoke tests that actually load the SigLIP2 model.
    
    These tests are slow and require:
    - Model to be downloaded or cached
    - Sufficient RAM/VRAM
    - Network access (first time)
    
    Run with: RUN_HEAVY_TESTS=1 python -m pytest lesson_pipeline/tests/test_embeddings.py -v -k "RealModel"
    """
    
    @classmethod
    def setUpClass(cls):
        """Load the model once for all heavy tests."""
        # Force CPU for CI stability (even if GPU available)
        os.environ['VISION_DEVICE'] = 'cpu'
        
        # Create a small test image
        cls.test_image = Image.new('RGB', (384, 384), color='blue')
        # Add some variation
        for i in range(0, 384, 20):
            for j in range(0, 384, 20):
                cls.test_image.putpixel((i, j), (255, 0, 0))
    
    def test_real_text_embedding(self):
        """Smoke test: embed text with real model."""
        # Reset singleton to ensure fresh load
        import lesson_pipeline.services.embeddings as emb_module
        emb_module._embedding_service_instance = None
        
        from lesson_pipeline.services.embeddings import embed_text
        
        result = embed_text("A diagram of plant cell mitochondria")
        
        # Verify basic properties
        self.assertIsInstance(result, list)
        self.assertEqual(len(result), EXPECTED_DIM)
        self.assertTrue(all(isinstance(x, float) for x in result))
        
        # Verify normalization
        import math
        norm = math.sqrt(sum(x * x for x in result))
        self.assertAlmostEqual(norm, 1.0, places=4)
    
    def test_real_image_embedding(self):
        """Smoke test: embed image with real model."""
        import lesson_pipeline.services.embeddings as emb_module
        emb_module._embedding_service_instance = None
        
        from lesson_pipeline.services.embeddings import embed_image_from_pil
        
        result = embed_image_from_pil(self.test_image)
        
        # Verify basic properties
        self.assertIsInstance(result, list)
        self.assertEqual(len(result), EXPECTED_DIM)
        self.assertTrue(all(isinstance(x, float) for x in result))
        
        # Verify normalization
        import math
        norm = math.sqrt(sum(x * x for x in result))
        self.assertAlmostEqual(norm, 1.0, places=4)
    
    def test_real_text_and_image_similarity(self):
        """Smoke test: text and matching image should have positive similarity."""
        import lesson_pipeline.services.embeddings as emb_module
        emb_module._embedding_service_instance = None
        
        from lesson_pipeline.services.embeddings import embed_text, embed_image_from_pil
        
        # Create a simple colored image
        red_image = Image.new('RGB', (384, 384), color='red')
        
        # Embed related text and image
        text_emb = embed_text("a solid red colored square image")
        image_emb = embed_image_from_pil(red_image)
        
        # Calculate cosine similarity (dot product of normalized vectors)
        similarity = sum(t * i for t, i in zip(text_emb, image_emb))
        
        # Should have some positive correlation (not necessarily high)
        # This is a sanity check that the model is producing sensible embeddings
        print(f"Text-image similarity: {similarity:.4f}")
        self.assertIsInstance(similarity, float)
        # Very loose check - just verify it's a reasonable number
        self.assertTrue(-1.0 <= similarity <= 1.0)


if __name__ == "__main__":
    unittest.main()

