"""
Shared types for the lesson generation pipeline.
"""
from typing import Optional, Dict, Any, List
from dataclasses import dataclass, field
from datetime import datetime, timezone
import uuid


@dataclass
class UserPrompt:
    """User's input prompt for lesson generation"""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    text: str = ""
    created_at: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


@dataclass
class ImagePlacement:
    """Normalized placement ratios for an image region."""
    x: float
    y: float
    width: float
    height: float
    scale: Optional[float] = None


@dataclass
class ScriptImageRequest:
    """A structured request for an image tied to a script segment."""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    prompt: str = ""
    placement: Optional[ImagePlacement] = None
    filename_hint: Optional[str] = None
    style: Optional[str] = None


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
    metadata: Dict[str, Any] = field(default_factory=dict)


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
    query: Optional[str] = None
    style: Optional[str] = None
    aspect_ratio: Optional[str] = None  # e.g. "16:9"
    size: Optional[str] = None          # e.g. "1024x576" or "medium"
    guidance_scale: Optional[float] = 7.5
    strength: Optional[float] = 0.7     # img2img strength
    time_offset: Optional[float] = None  # Seconds into lesson when LLM wants it
    duration: Optional[float] = None     # Seconds the image should stay visible
    placement: Dict[str, float] = field(default_factory=dict)  # x/y/width/height ratios
    metadata: Dict[str, Any] = field(default_factory=dict)     # Extra attributes direct from tag


@dataclass
class ImageSlot:
    """LLM-authored runtime instruction describing when/how to draw an image"""
    id: str
    tag: ImageTag
    sequence_index: int
    min_time_seconds: float = 0.0
    duration_seconds: float = 5.0
    placement: Dict[str, float] = field(default_factory=dict)
    notes: Optional[str] = None
    status: str = "pending"  # pending | queued | fulfilled


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
    vector_id: Optional[str] = None
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
    image_slots: List[ImageSlot] = field(default_factory=list)


@dataclass
class ScriptOutput:
    """Script output with optional image requests for downstream pipelines."""
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    prompt_id: str = ""
    content: str = ""
    image_requests: List[ScriptImageRequest] = field(default_factory=list)


@dataclass
class ResearchedImage:
    """Normalized image returned from research providers."""
    url: str
    source: Optional[str] = None
    title: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    license: Optional[str] = None
    raw: Dict[str, Any] = field(default_factory=dict)


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
        'metadata': candidate.metadata,
    }


def resolved_image_to_dict(resolved: ResolvedImage) -> Dict[str, Any]:
    """Convert ResolvedImage to dict for serialization"""
    return {
        'tag': {
            'id': resolved.tag.id,
            'prompt': resolved.tag.prompt,
            'query': resolved.tag.query,
            'style': resolved.tag.style,
            'aspect_ratio': resolved.tag.aspect_ratio,
            'size': resolved.tag.size,
            'guidance_scale': resolved.tag.guidance_scale,
            'strength': resolved.tag.strength,
        },
        'base_image_url': resolved.base_image_url,
        'final_image_url': resolved.final_image_url,
        'vector_id': resolved.vector_id,
        'metadata': resolved.metadata,
    }


def image_slot_to_dict(slot: ImageSlot) -> Dict[str, Any]:
    """Convert ImageSlot to dict for serialization"""
    return {
        'id': slot.id,
        'sequence_index': slot.sequence_index,
        'min_time_seconds': slot.min_time_seconds,
        'duration_seconds': slot.duration_seconds,
        'placement': slot.placement,
        'notes': slot.notes,
        'status': slot.status,
        'tag': {
            'id': slot.tag.id,
            'prompt': slot.tag.prompt,
            'query': slot.tag.query,
            'style': slot.tag.style,
            'aspect_ratio': slot.tag.aspect_ratio,
            'size': slot.tag.size,
            'guidance_scale': slot.tag.guidance_scale,
            'strength': slot.tag.strength,
            'time_offset': slot.tag.time_offset,
            'duration': slot.tag.duration,
            'placement': slot.tag.placement,
            'metadata': slot.tag.metadata,
        }
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
        'image_slots': [image_slot_to_dict(slot) for slot in lesson.image_slots],
    }


def image_placement_to_dict(placement: ImagePlacement) -> Dict[str, Any]:
    """Convert ImagePlacement to dict for serialization"""
    return {
        'x': placement.x,
        'y': placement.y,
        'width': placement.width,
        'height': placement.height,
        'scale': placement.scale,
    }


def script_image_request_to_dict(request: ScriptImageRequest) -> Dict[str, Any]:
    """Convert ScriptImageRequest to dict for serialization"""
    return {
        'id': request.id,
        'prompt': request.prompt,
        'placement': image_placement_to_dict(request.placement) if request.placement else None,
        'filename_hint': request.filename_hint,
        'style': request.style,
    }


def script_output_to_dict(script: ScriptOutput) -> Dict[str, Any]:
    """Convert ScriptOutput to dict for serialization"""
    return {
        'id': script.id,
        'prompt_id': script.prompt_id,
        'content': script.content,
        'image_requests': [
            script_image_request_to_dict(req) for req in script.image_requests
        ],
    }


def researched_image_to_dict(image: ResearchedImage) -> Dict[str, Any]:
    """Convert ResearchedImage to dict for serialization"""
    return {
        'url': image.url,
        'source': image.source,
        'title': image.title,
        'width': image.width,
        'height': image.height,
        'license': image.license,
        'raw': image.raw,
    }









