# vision/views.py
import json
from typing import List

from PIL import Image
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from .services.siglip2 import get_zero_shot_pipeline, encode_image_from_pil, encode_text


def _parse_labels(raw) -> List[str]:
    """
    Accept labels as:
    - JSON-encoded list string: '["cat", "dog"]'
    - Comma-separated string: 'cat, dog'
    - Already a Python list (from JSON body)
    """
    if raw is None:
        return []

    if isinstance(raw, list):
        return [str(x).strip() for x in raw if str(x).strip()]

    if isinstance(raw, str):
        raw = raw.strip()
        if not raw:
            return []
        # Try JSON first
        try:
            data = json.loads(raw)
            if isinstance(data, list):
                return [str(x).strip() for x in data if str(x).strip()]
        except json.JSONDecodeError:
            pass

        # Fallback: comma-separated
        return [part.strip() for part in raw.split(",") if part.strip()]

    # Unknown type; best effort
    return [str(raw).strip()] if str(raw).strip() else []


class Siglip2ZeroShotView(APIView):
    """
    POST /api/vision/zero-shot/

    Form-data:
      - image: file
      - labels: '["a cat", "a dog"]' or 'a cat, a dog'
    JSON:
      {
        "labels": ["a cat", "a dog"]
      }
      + image sent as multipart (most common case)
    """

    def post(self, request, *args, **kwargs):
        image_file = request.FILES.get("image")
        if image_file is None:
            return Response(
                {"detail": "Missing 'image' file in request."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        raw_labels = request.data.get("labels")
        labels = _parse_labels(raw_labels)

        if not labels:
            return Response(
                {"detail": "Provide at least one label via 'labels'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            image = Image.open(image_file).convert("RGB")
        except Exception as exc:
            return Response(
                {"detail": f"Could not read image: {exc}"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        classifier = get_zero_shot_pipeline()

        # SigLIP2 expects short label phrases
        outputs = classifier(image, candidate_labels=labels)

        # outputs is already JSON-serializable: list of dicts with label + score
        return Response(outputs, status=status.HTTP_200_OK)


class Siglip2EmbeddingView(APIView):
    """
    POST /api/vision/embed/

    Generate embeddings for images and/or text.

    Form-data:
      - image: file (optional)
      - text: string (optional)

    Returns:
      {
        "image_embedding": [1536-dimensional vector],  // if image provided
        "text_embedding": [1536-dimensional vector],   // if text provided
        "dimension": 1536
      }
    """

    def post(self, request, *args, **kwargs):
        image_file = request.FILES.get("image")
        text = request.data.get("text")

        if not image_file and not text:
            return Response(
                {"detail": "Provide at least one of 'image' or 'text'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        result = {"dimension": 1536}

        # Process image
        if image_file:
            try:
                image = Image.open(image_file).convert("RGB")
                embedding = encode_image_from_pil(image)
                result["image_embedding"] = embedding.tolist()
            except Exception as exc:
                return Response(
                    {"detail": f"Could not process image: {exc}"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # Process text
        if text and isinstance(text, str) and text.strip():
            try:
                embedding = encode_text(text.strip())
                result["text_embedding"] = embedding.tolist()
            except Exception as exc:
                return Response(
                    {"detail": f"Could not process text: {exc}"},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        return Response(result, status=status.HTTP_200_OK)









