"""
Shared types for the lesson generation pipeline.
"""
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field
from datetime import datetime
import uuid


@dataclass
class UserPrompt:
    """User's input prompt for lesson generation"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    text: str = ""
    created_at: str = field(default_factory=lambda: datetime.utcnow().isoformat())


@dataclass
class ImageCandidate:
    """Image found by the research phase"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    source_url: str = ""
    title: Optional[str] = None
    description: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    license: Optional[str] = None
    source: Optional[str] = None  # 'openstax', 'wikimedia', etc.
    tags: List[str] = field(default_factory=list)


@dataclass
class ImageEmbeddingRecord:
    """Image with vector embedding for Pinecone"""
    id: str
    image_url: str
    vector: List[float]
    topic_id: str
    original_prompt: str
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ImageTag:
    """Parsed IMAGE tag from script"""
    id: str
    prompt: str
    style: Optional[str] = None
    aspect_ratio: Optional[str] = None  # e.g. "16:9"
    size: Optional[str] = None          # e.g. "1024x576" or "medium"
    guidance_scale: Optional[float] = 7.5
    strength: Optional[float] = 0.7     # img2img strength


@dataclass
class ScriptDraft:
    """Raw script with IMAGE tags"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    prompt_id: str = ""
    content: str = ""  # raw text with [IMAGE ...] tags


@dataclass
class ResolvedImage:
    """Final image after matching and transformation"""
    tag: ImageTag
    base_image_url: str
    final_image_url: str
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class LessonDocument:
    """Final lesson output"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    prompt_id: str = ""
    content: str = ""  # final script with images injected
    images: List[ResolvedImage] = field(default_factory=list)
    topic_id: str = ""
    indexed_image_count: int = 0


# Helper functions for type conversions
def image_candidate_to_dict(candidate: ImageCandidate) -> Dict[str, Any]:
    """Convert ImageCandidate to dict for serialization"""
    return {
        'id': candidate.id,
        'source_url': candidate.source_url,
        'title': candidate.title,
        'description': candidate.description,
        'width': candidate.width,
        'height': candidate.height,
        'license': candidate.license,
        'source': candidate.source,
        'tags': candidate.tags,
    }


def resolved_image_to_dict(resolved: ResolvedImage) -> Dict[str, Any]:
    """Convert ResolvedImage to dict for serialization"""
    return {
        'tag': {
            'id': resolved.tag.id,
            'prompt': resolved.tag.prompt,
            'style': resolved.tag.style,
            'aspect_ratio': resolved.tag.aspect_ratio,
            'size': resolved.tag.size,
            'guidance_scale': resolved.tag.guidance_scale,
            'strength': resolved.tag.strength,
        },
        'base_image_url': resolved.base_image_url,
        'final_image_url': resolved.final_image_url,
        'metadata': resolved.metadata,
    }


def lesson_document_to_dict(lesson: LessonDocument) -> Dict[str, Any]:
    """Convert LessonDocument to dict for serialization"""
    return {
        'id': lesson.id,
        'prompt_id': lesson.prompt_id,
        'content': lesson.content,
        'images': [resolved_image_to_dict(img) for img in lesson.images],
        'topic_id': lesson.topic_id,
        'indexed_image_count': lesson.indexed_image_count,
    }


