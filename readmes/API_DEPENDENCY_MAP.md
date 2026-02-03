# Whiteboard API Dependency Map

**Purpose**: Document which backend API endpoints each frontend implementation uses.

---

## Endpoint Overview

### Active Endpoints

| Endpoint | Method | App | Status |
|----------|--------|-----|--------|
| `/api/timeline/generate/<session_id>/` | POST | timeline_generator | ✅ Active |
| `/api/timeline/<timeline_id>/` | GET | timeline_generator | ✅ Active |
| `/api/timeline/session/<session_id>/` | GET | timeline_generator | ✅ Active |
| `/api/lessons/start/` | POST | lessons | ✅ Active |
| `/api/lessons/<session_id>/` | GET | lessons | ✅ Active |
| `/api/lessons/<session_id>/next/` | POST | lessons | ✅ Active |
| `/api/lessons/diagram/` | POST | lessons | ✅ Active |
| `/api/wb/research/search/` | POST | wb_research | ✅ Active |
| `/api/wb/research/sources/` | GET | wb_research | ✅ Active |
| `/api/wb/preprocess/run/` | POST | wb_preprocess | ✅ Active |
| `/api/wb/vectorize/vectorize/` | POST | wb_vectorize | ✅ Active |
| `/api/wb/generate/vectors/<filename>` | GET | wb_generate | ✅ Active |
| `/api/wb/generate/font/<char_hex>.json` | GET | wb_generate | ✅ Active |
| `/api/lesson-pipeline/generate/` | POST | lesson_pipeline | ✅ Active |
| `/api/lesson-pipeline/image-proxy/` | GET | lesson_pipeline | ✅ Active |

### Disabled Endpoints

| Endpoint | Method | Status | Notes |
|----------|--------|--------|-------|
| `/api/whiteboard/objects/` | GET | ❌ Disabled | Commented in urls.py |
| `/api/whiteboard/objects/image/` | POST | ❌ Disabled | Commented in urls.py |
| `/api/whiteboard/objects/text/` | POST | ❌ Disabled | Commented in urls.py |
| `/api/whiteboard/objects/delete/` | DELETE | ❌ Disabled | Commented in urls.py |

---

## Frontend Dependencies

### 1. `frontend/lib/whiteboard/`

```
frontend/lib/whiteboard/
├── services/
│   ├── timeline_api_service.dart
│   │   └── Uses:
│   │       ├── POST /api/timeline/generate/<session_id>/
│   │       ├── GET  /api/timeline/<timeline_id>/
│   │       └── GET  /api/timeline/session/<session_id>/
│   │
│   ├── lesson_api_service.dart
│   │   └── Uses:
│   │       ├── POST /api/lessons/start/
│   │       ├── GET  /api/lessons/<session_id>/
│   │       └── POST /api/lessons/<session_id>/next/
│   │
│   └── whiteboard_backend_service.dart (DISABLED)
│       └── Would use:
│           ├── GET    /api/whiteboard/objects/
│           ├── POST   /api/whiteboard/objects/image/
│           ├── POST   /api/whiteboard/objects/text/
│           └── DELETE /api/whiteboard/objects/delete/
│
└── controllers/
    └── whiteboard_controller.dart
        └── Uses:
            └── GET /api/wb/generate/vectors/<filename>
```

#### Dependency Summary

| Endpoint | Service | Used For |
|----------|---------|----------|
| `POST /api/timeline/generate/<session_id>/` | TimelineApiService | Generate timeline with drawing actions |
| `GET /api/timeline/<timeline_id>/` | TimelineApiService | Fetch specific timeline |
| `GET /api/timeline/session/<session_id>/` | TimelineApiService | Get latest timeline for session |
| `POST /api/lessons/start/` | LessonApiService | Start new lesson session |
| `GET /api/lessons/<session_id>/` | LessonApiService | Get session details |
| `POST /api/lessons/<session_id>/next/` | LessonApiService | Advance to next segment |
| `GET /api/wb/generate/vectors/<filename>` | WhiteboardController | Load vector JSON for images |

#### Missing Dependencies (Not Currently Used)

| Endpoint | Would Be Used For |
|----------|-------------------|
| `POST /api/lessons/diagram/` | Diagram generation |
| `GET /api/lesson-pipeline/image-proxy/` | CORS-safe image fetching |
| `POST /api/lesson-pipeline/generate/` | Full lesson with images |

---

### 2. `whiteboard_demo/lib/main.dart`

```
whiteboard_demo/lib/
├── assistant_api.dart (AssistantApiClient)
│   └── Uses:
│       ├── POST /api/lessons/start/
│       ├── GET  /api/lessons/<session_id>/
│       ├── POST /api/lessons/<session_id>/next/
│       └── POST /api/lessons/<session_id>/raise-hand/
│
├── services/timeline_api.dart (TimelineApiClient)
│   └── Uses:
│       ├── POST /api/timeline/generate/<session_id>/
│       ├── GET  /api/timeline/<timeline_id>/
│       └── GET  /api/timeline/session/<session_id>/
│
├── services/lesson_pipeline_api.dart (LessonPipelineApi)
│   └── Uses:
│       ├── POST /api/lesson-pipeline/generate/
│       └── GET  /api/lesson-pipeline/image-proxy/?url=<url>
│
└── main.dart (_WhiteboardPageState)
    └── Uses:
        ├── POST /api/lessons/diagram/
        └── GET  /api/wb/generate/vectors/<filename> (implied)
```

#### Dependency Summary

| Endpoint | Client | Used For |
|----------|--------|----------|
| `POST /api/lessons/start/` | AssistantApiClient | Create lesson session |
| `GET /api/lessons/<session_id>/` | AssistantApiClient | Get session with lesson plan |
| `POST /api/lessons/<session_id>/next/` | AssistantApiClient | Get next segment |
| `POST /api/lessons/<session_id>/raise-hand/` | AssistantApiClient | Student Q&A interaction |
| `POST /api/timeline/generate/<session_id>/` | TimelineApiClient | Generate synchronized timeline |
| `GET /api/timeline/<timeline_id>/` | TimelineApiClient | Fetch timeline by ID |
| `GET /api/timeline/session/<session_id>/` | TimelineApiClient | Get session's timeline |
| `POST /api/lesson-pipeline/generate/` | LessonPipelineApi | Generate lesson with images |
| `GET /api/lesson-pipeline/image-proxy/` | LessonPipelineApi | CORS proxy for image URLs |
| `POST /api/lessons/diagram/` | Direct HTTP | Generate diagram images |

---

### 3. `visual_whiteboard/lib/main.dart`

```
visual_whiteboard/lib/main.dart
└── Uses:
    ├── GET    /api/whiteboard/objects/
    ├── POST   /api/whiteboard/objects/image/
    ├── POST   /api/whiteboard/objects/text/
    ├── DELETE /api/whiteboard/objects/delete/
    └── GET    /api/wb/generate/font/<char_hex>.json
```

#### Dependency Summary

| Endpoint | Used For |
|----------|----------|
| `GET /api/whiteboard/objects/` | Load all whiteboard objects on startup |
| `POST /api/whiteboard/objects/image/` | Create image object (x, y, scale) |
| `POST /api/whiteboard/objects/text/` | Create text object (prompt, letter_size) |
| `DELETE /api/whiteboard/objects/delete/` | Delete object by name |
| `GET /api/wb/generate/font/<char_hex>.json` | Load pre-vectorized font glyphs |

**Note**: The `/api/whiteboard/` endpoints are currently **disabled** in the backend. visual_whiteboard will not function without re-enabling them.

---

## Endpoint Details

### Timeline Endpoints

#### `POST /api/timeline/generate/<session_id>/`

**Request**:
```json
{
  "duration_target": 60.0,
  "regenerate": false
}
```

**Response**:
```json
{
  "timeline_id": 123,
  "segments": [
    {
      "sequence": 1,
      "start_time": 0.0,
      "end_time": 5.2,
      "speech_text": "Let's start with...",
      "audio_file": "segment_1_timestamp.mp3",
      "actual_audio_duration": 5.2,
      "drawing_actions": [
        {
          "type": "heading",
          "text": "PYTHAGOREAN THEOREM",
          "timing_hint": "appears as title"
        }
      ]
    }
  ],
  "total_duration": 62.5,
  "status": "ready"
}
```

#### `GET /api/timeline/<timeline_id>/`

Returns the same structure as generate, without regenerating.

#### `GET /api/timeline/session/<session_id>/`

Returns the latest timeline for a session.

---

### Lesson Endpoints

#### `POST /api/lessons/start/`

**Request**:
```json
{
  "topic": "Pythagorean Theorem",
  "level": "beginner",
  "duration": 60
}
```

**Response**:
```json
{
  "id": 456,
  "topic": "Pythagorean Theorem",
  "lesson_plan": ["Step 1...", "Step 2..."],
  "created_at": "2026-01-29T10:00:00Z"
}
```

#### `POST /api/lessons/diagram/`

**Request**:
```json
{
  "prompt": "right triangle with sides labeled a, b, c",
  "size": "256x256"
}
```

**Response**:
```json
{
  "image": "data:image/png;base64,iVBORw0KGgo...",
  "format": "png"
}
```

---

### Lesson Pipeline Endpoints

#### `POST /api/lesson-pipeline/generate/`

**Request**:
```json
{
  "prompt": "Explain photosynthesis",
  "subject": "Biology",
  "duration_target": 120
}
```

**Response**:
```json
{
  "lesson_id": "lesson_123",
  "title": "Photosynthesis",
  "segments": [...],
  "images": [
    {
      "id": "img_1",
      "base_image_url": "https://source.com/image.jpg",
      "final_image_url": "https://processed.com/image.png",
      "placement": {"x": 100, "y": 200, "width": 300, "height": 225}
    }
  ]
}
```

#### `GET /api/lesson-pipeline/image-proxy/?url=<url>`

Proxies image requests to avoid CORS issues. Returns the image binary.

---

### Whiteboard Object Endpoints (Disabled)

#### `POST /api/whiteboard/objects/image/`

**Request**:
```json
{
  "file_name": "diagram.json",
  "x": 100.0,
  "y": 200.0,
  "scale": 1.0
}
```

#### `POST /api/whiteboard/objects/text/`

**Request**:
```json
{
  "prompt": "Hello World",
  "x": 50.0,
  "y": 100.0,
  "letter_size": 180.0,
  "letter_gap": 20.0
}
```

---

## Dependency Matrix

| Endpoint | frontend/ | whiteboard_demo/ | visual_whiteboard/ |
|----------|:---------:|:----------------:|:------------------:|
| `/api/timeline/generate/` | ✅ | ✅ | ❌ |
| `/api/timeline/<id>/` | ✅ | ✅ | ❌ |
| `/api/timeline/session/` | ✅ | ✅ | ❌ |
| `/api/lessons/start/` | ✅ | ✅ | ❌ |
| `/api/lessons/<id>/` | ✅ | ✅ | ❌ |
| `/api/lessons/<id>/next/` | ✅ | ✅ | ❌ |
| `/api/lessons/<id>/raise-hand/` | ❌ | ✅ | ❌ |
| `/api/lessons/diagram/` | ❌ | ✅ | ❌ |
| `/api/lesson-pipeline/generate/` | ❌ | ✅ | ❌ |
| `/api/lesson-pipeline/image-proxy/` | ❌ | ✅ | ❌ |
| `/api/wb/generate/vectors/` | ✅ | 🔶 | ✅ |
| `/api/wb/generate/font/` | ❌ | ❌ | ✅ |
| `/api/whiteboard/objects/` | 🔶 | ❌ | ✅ |
| `/api/whiteboard/objects/image/` | 🔶 | ❌ | ✅ |
| `/api/whiteboard/objects/text/` | 🔶 | ❌ | ✅ |
| `/api/whiteboard/objects/delete/` | 🔶 | ❌ | ✅ |

**Legend**: ✅ = Used, ❌ = Not used, 🔶 = Has code but disabled/unused

---

## Unification Requirements

### Endpoints frontend/ Must Add Support For

1. **`POST /api/lessons/diagram/`** — For diagram generation
2. **`GET /api/lesson-pipeline/image-proxy/`** — For CORS-safe image fetching
3. **`POST /api/lesson-pipeline/generate/`** — For full lesson generation with images

### Endpoints to Evaluate

1. **`/api/whiteboard/objects/*`** — Currently disabled. Decision needed:
   - Re-enable for visual_whiteboard compatibility?
   - Or deprecate entirely?

2. **`/api/wb/generate/font/`** — Backend glyph rendering. Decision needed:
   - Port to frontend?
   - Or keep as fallback for complex glyphs?

---

## Recommended Service Structure

```
frontend/lib/whiteboard/services/
├── timeline_api_service.dart      # Keep as-is
├── lesson_api_service.dart        # Keep as-is
├── whiteboard_backend_service.dart # Keep but disabled
├── diagram_api_service.dart       # NEW: Port from whiteboard_demo
├── lesson_pipeline_api_service.dart # NEW: Port from whiteboard_demo
└── image_proxy_service.dart       # NEW: CORS proxy helper
```

---

*Last updated: 2026-01-29*  
*Related: WHITEBOARD_COMPARISON.md, FEATURE_PARITY_CHECKLIST.md*
