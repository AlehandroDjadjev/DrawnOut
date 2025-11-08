# 🎯 Lesson Pipeline Implementation - In Progress

## Overview

Building an end-to-end lesson generation system that:
1. **Researches images** from multiple sources in parallel
2. **Generates lesson script** with intelligent `[IMAGE ...]` tags
3. **Embeds images** using SigLIP and stores in Pinecone vector database
4. **Matches images** semantically to script tags via vector similarity
5. **Transforms images** using image-to-image models (ComfyUI)
6. **Assembles final lesson** with contextually relevant, customized visuals

---

## Architecture

```
User Prompt: "Explain DNA structure"
         │
         ▼
    /api/generate-lesson
         │
         ├──────────────────────┬──────────────────────┐
         │                      │                      │
         ▼                      ▼                      ▼
   IMAGE RESEARCH        SCRIPT GENERATION    (parallel)
   ├─ Search sources     ├─ GPT-4 generates
   ├─ Find 40 images     ├─ Adds [IMAGE...] tags
   ├─ Embed with SigLIP  └─ Returns script draft
   └─ Store in Pinecone
         │                      │
         └──────────┬───────────┘
                    ▼
            PARSE IMAGE TAGS
            [[IMAGE:img_1]]
                    │
                    ▼
         SEMANTIC IMAGE MATCHING
         ├─ Embed tag prompts
         ├─ Query Pinecone
         └─ Get best base images
                    │
                    ▼
         IMAGE-TO-IMAGE TRANSFORM
         ├─ Take base image
         ├─ Apply tag prompt
         └─ Generate final image
                    │
                    ▼
            INJECT INTO SCRIPT
            Return complete lesson
```

---

## ✅ Completed Components

### 1. Core Types (`lesson_pipeline/types.py`)
- ✅ `UserPrompt` - Input prompt
- ✅ `ImageCandidate` - Researched images
- ✅ `ImageEmbeddingRecord` - Vector database records
- ✅ `ImageTag` - Parsed IMAGE tags
- ✅ `ScriptDraft` - Raw script with tags
- ✅ `ResolvedImage` - Final images with metadata
- ✅ `LessonDocument` - Complete lesson output

### 2. Configuration (`lesson_pipeline/config.py`)
- ✅ Environment-based config
- ✅ Pinecone settings (API key, index name, environment)
- ✅ SigLIP model configuration
- ✅ ComfyUI server URL
- ✅ Timeouts, retries, defaults
- ✅ Loaded from environment variables

### 3. IMAGE Tag Parser (`lesson_pipeline/utils/image_tags.py`)
- ✅ Regex-based tag parsing
- ✅ Flexible attribute parsing (any order)
- ✅ Placeholder injection `[[IMAGE:id]]`
- ✅ Image injection with markdown format
- ✅ Validation for tags
- ✅ Support for: `id`, `prompt`, `style`, `aspect`, `size`, `strength`, `guidance`

**Example:**
```
[IMAGE id="img_1" prompt="DNA double helix" style="scientific diagram" aspect="16:9"]
→ Parsed to ImageTag object
→ Replaced with [[IMAGE:img_1]]
→ Later injected as: ![DNA double helix](https://...){.lesson-image}
```

### 4. SigLIP Embedding Service (`lesson_pipeline/services/embeddings.py`)
- ✅ Text embedding via SigLIP
- ✅ Image embedding via SigLIP  
- ✅ Batch processing for efficiency
- ✅ GPU support (CUDA)
- ✅ Lazy model loading
- ✅ Error handling
- ✅ Singleton pattern

**Features:**
- Model: `google/siglip-so400m-patch14-384`
- Output: 1152-dimensional vectors
- Batched inference (8 images at a time)
- Normalized embeddings for cosine similarity

### 5. Pinecone Vector Store (`lesson_pipeline/services/vector_store.py`)
- ✅ Index management (auto-create)
- ✅ Batch upsert (100 vectors at a time)
- ✅ Semantic search with filters
- ✅ Topic-based filtering
- ✅ Metadata storage
- ✅ Stats API
- ✅ Delete by topic

**Features:**
- Index: `lesson-images`
- Metric: Cosine similarity
- Serverless (AWS)
- Automatic batching

---

## 🔄 In Progress Components

### 6. Image Research Integration (NEXT)
File: `lesson_pipeline/services/image_researcher.py`

**Needed:**
- Wrapper around existing `image_researcher` app
- Interface: `research_images(prompt: str, subject: str, max_images: int) -> List[ImageCandidate]`
- Convert image_researcher results to `ImageCandidate` format

### 7. Script Writer Service (NEXT)
File: `lesson_pipeline/services/script_writer.py`

**Needed:**
- Wrapper around existing timeline generator or new GPT-4 service
- System prompt that instructs LLM to use `[IMAGE ...]` tags
- Interface: `generate_script(prompt: UserPrompt) -> ScriptDraft`

**System Prompt Example:**
```
You are an educational content writer. Generate a lesson script with embedded image tags.

For each visual concept, add: [IMAGE id="unique_id" prompt="descriptive prompt" style="photo|diagram|illustration" aspect="16:9"]

Example:
The neuron is the basic building block...
[IMAGE id="img_1" prompt="labeled diagram of a neuron showing dendrites, cell body, axon" style="scientific diagram" aspect="16:9"]
```

### 8. Image-to-Image Service (NEXT)
File: `lesson_pipeline/services/image_to_image.py`

**Needed:**
- Integration with ComfyUI (existing `imggen` app)
- Interface: `transform_image(base_url: str, prompt: str, params: dict) -> str`
- Handle style transfer, aspect ratio adjustment
- Return final image URL

### 9. Pipeline Orchestration (NEXT)
File: `lesson_pipeline/pipelines/orchestrator.py`

**Needed:**
- `generate_lesson(prompt: str, subject: str) -> LessonDocument`
- Coordinate all steps:
  1. Parallel: research images + generate script
  2. Parse IMAGE tags
  3. Resolve tags to base images (Pinecone query)
  4. Transform images (img2img)
  5. Inject into script
  6. Return LessonDocument

### 10. API Endpoint (NEXT)
File: `lesson_pipeline/views.py`

**Needed:**
- `POST /api/lesson-pipeline/generate/`
- Request: `{ "prompt": "...", "subject": "..." }`
- Response: `LessonDocument` JSON
- Error handling
- Logging

---

## Dependencies

### Python Packages Needed
```bash
# Already installed:
- transformers
- tokenizers
- torch
- Pillow
- requests

# Need to add:
pip install pinecone-client
```

### Environment Variables
```bash
# .env file
PINECONE_API_KEY=your_api_key
PINECONE_ENVIRONMENT=us-east-1-aws
PINECONE_INDEX_NAME=lesson-images

SIGLIP_MODEL_NAME=google/siglip-so400m-patch14-384
EMBEDDING_DIMENSION=1152

COMFY_SERVER_URL=http://127.0.0.1:8188

MAX_IMAGES_PER_PROMPT=40
DEFAULT_ASPECT_RATIO=16:9
DEFAULT_SIZE=1024x576
```

---

## File Structure

```
backend/lesson_pipeline/
├── __init__.py                    ✅ Package init
├── apps.py                        ✅ Django app config
├── types.py                       ✅ Shared data types
├── config.py                      ✅ Configuration
│
├── utils/
│   ├── __init__.py                ✅
│   └── image_tags.py              ✅ IMAGE tag parser
│
├── services/
│   ├── __init__.py                🔄 TODO
│   ├── embeddings.py              ✅ SigLIP service
│   ├── vector_store.py            ✅ Pinecone service
│   ├── image_researcher.py        🔄 TODO (wrapper)
│   ├── script_writer.py           🔄 TODO (wrapper/new)
│   └── image_to_image.py          🔄 TODO (ComfyUI wrapper)
│
├── pipelines/
│   ├── __init__.py                🔄 TODO
│   ├── image_ingestion.py         🔄 TODO (research → Pinecone)
│   ├── image_resolver.py          🔄 TODO (tags → base images)
│   ├── image_transformation.py    🔄 TODO (img2img batch)
│   └── orchestrator.py            🔄 TODO (main pipeline)
│
├── views.py                       🔄 TODO (API endpoint)
├── urls.py                        🔄 TODO (URL routing)
└── README.md                      🔄 TODO (documentation)
```

---

## Next Steps

### Immediate (Phase 2):
1. ✅ Create `services/__init__.py`
2. ✅ Create `services/image_researcher.py` wrapper
3. ✅ Create `services/script_writer.py` with IMAGE tag instructions
4. ✅ Create `services/image_to_image.py` ComfyUI wrapper

### Phase 3:
5. Create `pipelines/image_ingestion.py`
6. Create `pipelines/image_resolver.py`
7. Create `pipelines/image_transformation.py`
8. Create `pipelines/orchestrator.py`

### Phase 4:
9. Create API endpoint in `views.py`
10. Add URL routing in `urls.py`
11. Register app in Django settings
12. Install `pinecone-client`
13. Create test endpoint

### Phase 5:
14. Integration testing
15. Error handling improvements
16. Logging enhancements
17. Performance optimization
18. Documentation

---

## Testing Plan

### Unit Tests
- ✅ IMAGE tag parser
- ⏳ Embedding service (mock model)
- ⏳ Vector store (mock Pinecone)
- ⏳ Each pipeline component

### Integration Tests
- ⏳ Full pipeline with real data
- ⏳ Error scenarios
- ⏳ Parallel execution
- ⏳ Timeout handling

### End-to-End Test
```bash
curl -X POST http://localhost:8000/api/lesson-pipeline/generate/ \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "Explain DNA structure and replication",
    "subject": "Biology"
  }'
```

Expected output:
- Complete lesson script with images injected
- 5-10 contextually relevant images
- Each image transformed to match style/requirements
- Total time: 30-90 seconds

---

## Current Status

**Phase 1: COMPLETE** ✅
- Core types defined
- Configuration system
- IMAGE tag parser
- SigLIP embedding service
- Pinecone vector store

**Phase 2: IN PROGRESS** 🔄
- Image researcher wrapper
- Script writer service
- Image-to-image service

**Estimated Completion:** ~4-6 more hours of development

---

## Design Decisions

### Why SigLIP?
- State-of-the-art vision-language model
- Better than CLIP for text-image matching
- 1152-dim embeddings balance quality/speed
- Native multimodal understanding

### Why Pinecone?
- Managed vector database (no ops)
- Fast similarity search at scale
- Metadata filtering
- Serverless scaling

### Why Image-to-Image?
- Base images provide structure/context
- Transformation allows style consistency
- Better quality than pure text-to-image
- Faster generation

### Why Parallel Research + Script?
- Saves ~30-60 seconds
- Images and script don't depend on each other
- Better user experience
- Efficient resource usage

---

**Status:** 🟡 **40% Complete** - Core infrastructure done, pipeline integration in progress


