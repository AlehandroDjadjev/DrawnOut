# DrawnOut — AI-Synchronized Whiteboard Lessons
### Programming Olympiad Documentation

---

## Administrative Information

| Field | Value |
|---|---|
| **Project name** | DrawnOut — AI-generated synchronized whiteboard lessons (speech + animated drawing) |
| **Category** | Programming — Software system (client–server + cross-platform client) |
| **Version** | 1.0 |
| **Date** | \[Fill in\] |
| **Repository** | AlehandroDjadjev/DrawnOut |

---

## 1. Тема

**DrawnOut** — AI-базирана образователна система за синхронизирани уроци с нарация и анимирано рисуване на дъска.

**One-sentence purpose:** Given a topic, the system generates a structured lesson timeline containing narrated speech segments and whiteboard drawing actions; during playback, audio and drawing execute simultaneously so the student sees exactly what the tutor is explaining at that moment.

---

## 2. Автори

| Field | Author 1 | Author 2 |
|---|---|---|
| Three names | \[Fill in\] | \[Fill in\] |
| EGN | \[Fill in\] | \[Fill in\] |
| Address | \[Fill in\] | \[Fill in\] |
| Phone | \[Fill in\] | \[Fill in\] |
| Email | \[Fill in\] | \[Fill in\] |
| School | \[Fill in\] | \[Fill in\] |
| Grade | \[Fill in\] | \[Fill in\] |

**Author 1 — Role:** Backend architecture; timeline generation service; audio synthesis pipeline; lesson pipeline orchestration; Pinecone vector database integration; API endpoint design; data model and serialization.

**Author 2:** Flutter whiteboard engine; cubic Bézier stroke rendering; font glyph rendering system; backend image player widget; timeline playback synchronization; UI/UX design and navigation.

---

## 3. Ръководител

| Field | Value |
|---|---|
| Three names | \[Fill in\] |
| Phone | \[Fill in\] |
| Email | \[Fill in\] |
| Position | \[Fill in\] |

---

## 4. Резюме

### 4.1. Цели

#### Problem statement

In most learning materials, narration and visuals are loosely coupled: a teacher finishes explaining concept A while the board still shows concept B. DrawnOut treats **timing alignment as a first-class software requirement** by building an explicit, machine-validated timeline where every speech segment is directly bound to its drawing actions.

#### Solution

The backend produces a `segments[]` JSON array where every segment contains `speech_text`, `audio_file`, and `drawing_actions[]`. The Flutter client plays each audio segment and triggers the corresponding drawing actions concurrently — text is written using pre-generated handwriting font glyphs, and educational diagrams are drawn as animated cubic Bézier stroke paths sourced from the image pipeline.

#### Engineering novelties

| Feature | Description |
|---|---|
| **Structured timeline contract** | LLM output is constrained to `{"type":"json_object"}` and validated field-by-field before acceptance |
| **Two-phase timing** | Durations are estimated first, audio is synthesized second, then `actual_audio_duration` is measured and timings are recomputed |
| **Handwriting font system** | Glyphs are pre-processed to cubic Bézier stroke JSON; the client fetches and renders them via a REST API, producing authentic handwriting animation |
| **Pre-computed image strokes** | The `whiteboard_backend` image pipeline researches, selects, vectorizes, and upserts images into Pinecone; the lesson orchestrator resolves `[IMAGE ...]` tags via embedding similarity and sends pre-computed strokes to the client |
| **Stroke animation engine** | The Flutter `WhiteboardPainter` uses per-stroke curvature timing, a physics-based speed warp, and hand-wobble effects ported from the DrawnOut desktop whiteboard prototype |

#### Quick demo path (for judges)

1. Start Django server: `python manage.py runserver`
2. Start Flutter app: `flutter run -d chrome`
3. Enter a topic and tap **Start Lesson**
4. Watch audio narration and animated whiteboard drawing execute in sync, segment by segment

---

### 4.2. Основни етапи в реализирането на проекта

#### Stage A — Core backend: sessions, timelines, and audio

- Implemented `timeline_generator` service: produces structured JSON with `response_format={"type":"json_object"}`, validates required fields per segment (`sequence`, `speech_text`, `estimated_duration`, `drawing_actions`), and computes cumulative `start_time` / `end_time`.
- Implemented per-segment audio synthesis (Cloud TTS); measures `actual_audio_duration` from synthesized files; recomputes the full timeline using real durations via `_recompute_timings()`.

#### Stage B — Playback synchronization in Flutter

- Defined the `TimelineSegment` / `DrawingAction` / `SyncedTimeline` data models — the timeline is the single source of truth for both audio and drawing.
- Implemented `TimelinePlaybackController`: for each segment it loads the audio URL, triggers drawing actions asynchronously, starts audio, and waits for completion before advancing.

#### Stage C — Whiteboard action engine and layout

- Implemented `WhiteboardOrchestrator`: owns layout config, block placement (headings, bullets, formulas, images), and routes each `drawing_action` through a unified handler.
- Implemented `sketch_image` handling: when `metadata['strokes']` is present the pre-computed cubic Bézier stroke JSON is decoded and placed directly; no image fetch or re-vectorization required.

#### Stage D — `whiteboard_backend` image pipeline

- `ImagePipeline.py` implements the full flow: DuckDuckGo + API image research → Qwen VL model selection → SigLIP embedding → stroke vectorization → Pinecone upsert.
- Exposed as `POST /api/wb/pipeline/image-pipeline/` returning `{ id, embedding, strokes }` per image.
- `lesson_pipeline` orchestrator pre-populates Pinecone before script generation; after the script is ready it resolves `[IMAGE ...]` tags via cosine similarity search and injects stroke JSON into `drawing_actions`.

#### Stage E — Handwriting font glyph system

- `whiteboard_backend` serves pre-generated cubic Bézier glyph files from `Font/<hex>.json` via `GET /api/wb/pipeline/font/glyph/<hex>/` and font metrics via `GET /api/wb/pipeline/font/metrics/`.
- Flutter `FontGlyphService` fetches and caches glyphs; `renderLines()` implements the full text layout engine (cursor advance, baseline alignment, multi-line flow) and returns world-space polylines for the existing animation pipeline.

#### Stage F — DrawnOutWhiteboard rendering engine integration

- Ported `WhiteboardPainter`, `DrawableStroke`, and the per-stroke timing system from the DrawnOutWhiteboard desktop prototype into the whiteboard_demo Flutter app.
- Added `BackendStrokeService` (cubic Bézier → `DrawableStroke` with wobble, curvature timing, travel pauses) and `BackendImagePlayer` widget (self-contained animated image playback).

---

## 5. Описание на системата

### 5.1. Архитектура

```
┌──────────────────────────────────────────────────────────────┐
│                      Flutter Client                          │
│   WhiteboardOrchestrator ──► WhiteboardPainter              │
│   TimelinePlaybackController ──► SketchPlayer               │
│   FontGlyphService (text)   BackendImagePlayer (images)      │
└────────────────────┬─────────────────────────────────────────┘
                     │ REST / JSON
┌────────────────────▼─────────────────────────────────────────┐
│                   Django Backend (port 8000)                  │
│                                                              │
│  ┌─────────────────────┐    ┌──────────────────────────────┐ │
│  │   lesson_pipeline   │    │     whiteboard_backend       │ │
│  │                     │    │                              │ │
│  │  orchestrator.py    │───►│  POST image-pipeline/        │ │
│  │  script_writer.py   │    │  GET  font/metrics/          │ │
│  │  whiteboard_image_  │    │  GET  font/glyph/<hex>/      │ │
│  │    service.py       │    │                              │ │
│  └─────────────────────┘    │  ImagePipeline.py            │ │
│                             │  ProccessFont.py             │ │
│  ┌──────────────────────┐   │  StrokeVectors/  Font/       │ │
│  │  timeline_generator  │   └──────────────────────────────┘ │
│  │  TTSVoice            │                                    │
│  │  lessons / users     │    ┌──────────────────────────────┐ │
│  └──────────────────────┘   │  Pinecone (vector DB)        │ │
│                             │  SigLIP embeddings           │ │
└─────────────────────────────┴──────────────────────────────--┘
```

### 5.2. Active API Endpoints

#### `whiteboard_backend` — `/api/wb/pipeline/`

| Method | Path | Description |
|---|---|---|
| `POST` | `image-pipeline/` | Research → select → vectorize → upsert images. Returns `{ id, embedding, strokes }` per prompt. |
| `GET` | `font/metrics/` | Returns `font_metrics.json` (line height, ascent, descent, image dimensions). |
| `GET` | `font/glyph/<hex4>/` | Returns the cubic Bézier stroke JSON for a single glyph. `hex4` = 4-char Unicode code point (e.g. `0041` = 'A'). |

#### `lesson_pipeline` — `/api/lesson-pipeline/`

| Method | Path | Description |
|---|---|---|
| `POST` | `generate/` | Generate a complete lesson: script, image resolution, audio synthesis, and timeline assembly. |

#### `timeline_generator` — `/api/timeline/`

| Method | Path | Description |
|---|---|---|
| `POST` | `generate/<session_id>/` | Generate or retrieve a structured timeline for a session. |
| `GET` | `retrieve/<session_id>/` | Fetch a previously generated timeline. |

#### `lessons` — `/api/lessons/`

| Method | Path | Description |
|---|---|---|
| `POST` | `sessions/` | Create a new lesson session. |
| `GET` | `sessions/<id>/` | Retrieve session details and status. |

#### `users` — `/api/auth/`

| Method | Path | Description |
|---|---|---|
| `POST` | `register/` | Register a new user. |
| `POST` | `login/` | Authenticate and receive token. |

> **Note:** The legacy apps `wb_research`, `wb_preprocess`, `wb_vectorize`, and `wb_generate` remain registered in `urls.py` for backward compatibility but are **not used in the current lesson generation flow**. All image research, vectorization, and font serving is handled exclusively by `whiteboard_backend`.

### 5.3. Core Data Contract — Timeline JSON

```json
{
  "timeline_id": 42,
  "session_id": 7,
  "total_duration": 94.3,
  "segments": [
    {
      "sequence": 1,
      "start_time": 0.0,
      "end_time": 12.4,
      "speech_text": "The cell membrane is a phospholipid bilayer...",
      "audio_file": "/media/audio/seg_1.mp3",
      "actual_audio_duration": 12.4,
      "drawing_actions": [
        { "type": "heading",  "text": "Cell Membrane" },
        { "type": "bullet",   "text": "Phospholipid bilayer", "level": 1 },
        {
          "type": "sketch_image",
          "text": "cell membrane diagram",
          "placement": { "x": 0.55, "y": 0.3, "width": 0.4, "height": 0.35 },
          "metadata": {
            "pipeline_id": "processed_12",
            "strokes": { "vector_format": "bezier_cubic", "width": 800,
                         "height": 600, "strokes": [ "..." ] },
            "embedding": [ 0.021, -0.14, "..." ]
          }
        }
      ]
    }
  ]
}
```

**Key rule:** The UI never infers what to draw — it only executes `drawing_actions[]` as received from the backend.

### 5.4. End-to-End Data Flow (Topic → Lesson Playback)

```
User enters topic
       │
       ▼
lesson_pipeline/orchestrator.py
  ├── Step 1: POST image-pipeline/ (main topic) ──► whiteboard_backend
  │           ↳ Research + vectorize + upsert to Pinecone (runs in background thread)
  │
  ├── Step 2: Generate script (parallel with Step 1)
  │           script_writer.py ──► GPT-4o → script with [IMAGE tag] markers
  │
  ├── Step 3: Wait for Pinecone population to finish
  │
  ├── Step 4: Resolve [IMAGE ...] tags
  │           POST image-pipeline/ (per-tag prompts) ──► Pinecone similarity search
  │           ↳ Returns { id, strokes, embedding } for each tag
  │
  ├── Step 5: Build drawing_actions[] with stroke JSON in metadata
  │
  ├── Step 6: Synthesize audio per segment (TTSVoice)
  │           ↳ Measure actual_audio_duration, recompute timings
  │
  └── Step 7: Return complete SyncedTimeline JSON
```

```
Flutter client receives SyncedTimeline
       │
       ▼
TimelinePlaybackController (segment loop)
  ├── Load audio URL for segment
  ├── Trigger drawing_actions[] (non-blocking)
  │     ├── heading/bullet/formula ──► FontGlyphService.renderLines()
  │     │     ↳ GET font/glyph/<hex>/ (cached) ──► cubic Bézier polylines
  │     │     ↳ WhiteboardPainter animates stroke-by-stroke
  │     │
  │     └── sketch_image ──► metadata['strokes'] present?
  │           ├── YES: BackendStrokeService.toPolylines() ──► SketchPlayer
  │           └── NO:  fetch URL → BackendVectorizer.vectorize()
  │
  └── Play audio, wait for completion, advance to next segment
```

---

## 6. Описание на приложението (UI Guide)

### 6.1. Screens Overview

The whiteboard_demo Flutter app has five main screens, accessible from the bottom navigation bar or the main menu.

```
┌──────────────────────────────────┐
│  ①  ②  ③  ④  ⑤   ← nav bar   │
└──────────────────────────────────┘
① Home / Lesson start
② Lesson history
③ Live whiteboard (manual)
④ Market / lesson library
⑤ Settings
```

---

### 6.2. Screen 1 — Home / Lesson Start

**What it does:** Entry point for generating a new synchronized lesson. The user enters a topic, optionally adjusts settings, and starts the generation.

**How to navigate:**
1. Type a topic into the text field (e.g. *"Pythagorean theorem"*).
2. Tap **Start Lesson** — the backend generates the full timeline (script + images + audio) in one call; a loading indicator shows progress.
3. Lesson playback begins automatically once generation completes.

> 📷 **\[IMAGE PLACEHOLDER — Home screen: topic input field + Start Lesson button\]**
> *(Insert screenshot here)*

---

### 6.3. Screen 2 — Lesson Playback (Whiteboard)

**What it does:** Plays back the synchronized lesson. Audio narration and whiteboard drawing happen simultaneously — text is written in handwriting strokes, educational diagrams are drawn as animated line art.

**UI elements:**

| Element | Description |
|---|---|
| **Whiteboard canvas** | Full-screen area where strokes are animated. White background, black handwriting. |
| **Playback bar** (bottom) | Shows current segment, total duration, pause/resume button, and segment progress indicator. |
| **Segment indicator** | Small pill at the top showing "Segment 3 / 12". |
| **Pause / Resume** | Tapping anywhere on the playback bar pauses both audio and drawing animation simultaneously. |
| **Skip segment** | Swipe right on the playback bar to advance to the next segment. |

**How to navigate:**
1. Lesson starts automatically after generation.
2. Each segment's audio plays while its drawing actions appear on the canvas.
3. When a segment finishes, the canvas clears and the next segment's content is drawn.
4. Tap the **⏸ pause** button to freeze both audio and animation. Tap again to resume.
5. When the last segment completes, the **Lesson Complete** overlay appears.

> 📷 **\[IMAGE PLACEHOLDER — Lesson playback: whiteboard with animated text being drawn, audio wave indicator visible at bottom\]**
> *(Insert screenshot here)*

> 📷 **\[IMAGE PLACEHOLDER — Lesson playback: an educational diagram (e.g. cell membrane) being drawn as animated strokes while the audio narration bar shows the current segment\]**
> *(Insert screenshot here)*

---

### 6.4. Screen 3 — Lesson Complete Overlay

**What it does:** Shown at the end of a lesson. Summarizes the topic, total duration, and provides options to replay or go back to the home screen.

> 📷 **\[IMAGE PLACEHOLDER — Lesson complete overlay: "Great job! You just learned about Pythagorean Theorem" with replay and home buttons\]**
> *(Insert screenshot here)*

---

### 6.5. Screen 4 — Lesson History

**What it does:** Lists all previously generated lessons for the current user. Each entry shows topic, date, and duration. Tapping any entry replays that lesson (fetches the saved timeline from the backend — no regeneration).

**How to navigate:**
1. Open from nav bar (② icon).
2. Tap any lesson card to rewatch it.
3. Long-press a card to delete the session.

> 📷 **\[IMAGE PLACEHOLDER — Lesson history screen: list of lesson cards with topic title, date, and duration badge\]**
> *(Insert screenshot here)*

---

### 6.6. Screen 5 — Settings

**What it does:** Lets the user configure backend URL, drawing speed, and developer options.

| Setting | Description |
|---|---|
| **Backend URL** | The Django server address (default: `http://localhost:8000`). Change this for production or demo deployments. |
| **Drawing speed** | Slider from 0.5× (slow, visible stroke-by-stroke) to 3× (fast). |
| **Developer mode** | Toggle to show per-segment debug overlay and API timing logs. |

> 📷 **\[IMAGE PLACEHOLDER — Settings screen: backend URL field, drawing speed slider, developer mode toggle\]**
> *(Insert screenshot here)*

---

### 6.7. Developer Mode — Debug Overlay

When Developer Mode is enabled (Settings screen), a small overlay panel appears on the whiteboard during playback. It shows:
- Current segment index and total count
- `actual_audio_duration` vs `estimated_duration` for the current segment
- Number of drawing actions in the segment and their types
- Timing drift between audio and drawing completion

> 📷 **\[IMAGE PLACEHOLDER — Developer overlay panel (semi-transparent) showing segment timing data over the whiteboard canvas\]**
> *(Insert screenshot here)*

---

## 7. Реализация

### 7.1. Backend Technology Choices

| Choice | Justification |
|---|---|
| **Django (Python)** | Stable ORM for session/timeline persistence; clean routing for REST endpoints; rich ecosystem for audio and image processing. |
| **GPT-4o via OpenAI API** | `response_format={"type":"json_object"}` enforces machine-readable output; high-quality script generation in one call. |
| **Google Cloud TTS** | Reliable per-segment audio synthesis; returns MP3 files with known duration. |
| **Pinecone** | Vector database for storing and querying SigLIP image embeddings; enables semantic `[IMAGE ...]` tag resolution by cosine similarity. |
| **SigLIP (Google)** | Multi-modal embedding model; maps both images and text prompts to the same vector space for similarity matching. |
| **Qwen VL** | Vision-language model used to select the best image from research results for each educational concept. |

### 7.2. `whiteboard_backend` — Image Pipeline Detail

The full flow for one image (from prompt to drawable strokes):

```
1. Image Research
   DDG search + Wikimedia API + other sources
   ↓
2. Deduplication
   SHA-1 hash; skip already-processed images
   ↓
3. Qwen VL Selection
   Rank candidate images for educational relevance
   ↓
4. SigLIP Embedding
   Produce 1536-dim embedding vector
   ↓
5. Stroke Vectorization (ImageVectorizer.py)
   Preprocess (Canny) → Skeletonize → Trace graph →
   Split at corners → Simplify → Export bezier_cubic JSON
   ↓
6. Pinecone Upsert
   Store { id, embedding, metadata: { strokes, pipeline_id } }
```

**Key output format** (`StrokeVectors/<id>.json`):
```json
{
  "vector_format": "bezier_cubic",
  "width": 800, "height": 600,
  "strokes": [
    {
      "segments": [[x0,y0, cx1,cy1, cx2,cy2, x1,y1], ...],
      "color_group_id": 11
    }
  ]
}
```

### 7.3. `whiteboard_backend` — Font Glyph System

Pre-processing (`ProccessFont.py` / `ProcessFont.py`):
1. Render each Unicode character to a 2048×2048 canvas at a fixed font size (512px).
2. Skeletonize using OpenCV thinning.
3. Vectorize to cubic Bézier strokes.
4. Save as `Font/<hex4>.json` (e.g. `0041.json` for 'A').
5. Write `Font/font_metrics.json` with `line_height_px`, `ascent_px`, `descent_px`, `image_height`.

The Flutter `FontGlyphService` fetches glyphs on demand and caches them. `renderLines()` reproduces the exact layout algorithm from the DrawnOutWhiteboard desktop prototype: cursor advance, baseline alignment, and per-character scale derived from `fontSize / line_height_px`.

### 7.4. Flutter — Rendering Engine

The whiteboard_demo rendering stack (bottom to top):

| Layer | Class | Role |
|---|---|---|
| Data | `DrawableStroke` | Points, timing weights, curvature, wobble, color |
| Parsing | `BackendStrokeService` | Cubic Bézier JSON → `DrawableStroke[]` with timing |
| Text | `FontGlyphService` | Glyph API fetch/cache → world-space polylines |
| Painter | `WhiteboardPainter` | `CustomPainter` with speed warp (accel→peak→decel), per-stroke color, step mode |
| Animation | `SketchPlayer` / `BackendImagePlayer` | `AnimationController`-driven playback widgets |
| Layout | `LayoutState` / `WhiteboardOrchestrator` | Block placement, column flow, cursor tracking |
| Sync | `TimelinePlaybackController` | Segment-by-segment audio + drawing coordination |

**Speed warp formula** (within each stroke, ported from DrawnOutWhiteboard):
```
t → warped_t  using  accel [0..t1] → peak [t1..t2] → cruise [t2..t3] → decel [t3..1]
Each segment interpolated with smootherstep for natural feel.
```

---

## 8. Инсталация и стартиране

### 8.1. Requirements

- Python 3.10+, Django 4.x
- Flutter 3.x (web target)
- GPU recommended for Qwen VL (CPU fallback supported)
- Environment keys: `OPENAI_API_KEY`, `Pinecone-API-Key`, `GOOGLE_APPLICATION_CREDENTIALS` (TTS)

### 8.2. Backend

```bash
cd DrawnOut/backend
pip install -r requirements.txt

# Copy and fill in your secrets
cp .env.example .env
# Edit .env: OPENAI_API_KEY, Pinecone-API-Key, etc.

python manage.py migrate
python manage.py runserver
```

> ⚠️ **Do not commit `.env` to the repository.** The file contains secret keys. Provide `.env.example` with placeholder values for the submission archive.

### 8.3. Pre-populate font glyphs (one-time)

```bash
cd DrawnOut/backend/whiteboard_backend
python ProccessFont.py   # generates Font/<hex>.json + font_metrics.json
```

### 8.4. Frontend

```bash
cd DrawnOut/whiteboard_demo
flutter pub get
flutter run -d chrome   # or: flutter run -d windows
```

Open `http://localhost:8000` in Settings if the backend URL differs.

---

## 9. Заключение

### 9.1. Main Result

DrawnOut demonstrates an end-to-end synchronized lesson pipeline:
- A strict JSON timeline contract binds each speech segment to its drawing actions.
- Audio duration is measured after synthesis and fed back to recompute timing — eliminating drift.
- Text is drawn using pre-generated handwriting glyphs (cubic Bézier) fetched from the backend, not re-rendered on the client.
- Educational diagrams are pre-vectorized by the image pipeline and sent as stroke JSON — the client draws them without any image processing at runtime.
- All stroke animation uses the same physics-based engine (curvature timing, speed warp, wobble) as the standalone DrawnOutWhiteboard desktop prototype.

### 9.2. Known Limitations

| Limitation | Status |
|---|---|
| External API keys required (OpenAI, TTS, Pinecone) | Documented in `.env.example`; graceful error messages on missing keys |
| Qwen VL requires GPU for best performance | CPU fallback implemented; slower but functional |
| Font coverage limited to pre-generated glyphs | 95 glyphs covering ASCII printable range (codes 0x0021–0x007E) |
| Legacy apps (`wb_research`, `wb_preprocess`, `wb_vectorize`, `wb_generate`) still registered in `urls.py` | Not used in lesson flow; present for backward compatibility only |

### 9.3. Appendix Checklist (replace with screenshots in final PDF)

- [ ] `python manage.py migrate` completes without errors
- [ ] Font glyph files present in `whiteboard_backend/Font/` (≥ 90 `.json` files)
- [ ] `GET /api/wb/pipeline/font/metrics/` returns 200 with `line_height_px`
- [ ] `POST /api/wb/pipeline/image-pipeline/` returns strokes for a test prompt
- [ ] `POST /api/lesson-pipeline/generate/` returns a valid `SyncedTimeline`
- [ ] Flutter app loads, topic entry works, lesson generation completes
- [ ] Whiteboard canvas shows animated handwriting during playback
- [ ] Audio plays in sync with drawing actions
- [ ] Segment transitions clear the canvas and start fresh
- [ ] Lesson Complete overlay appears at the end

---

*Document version 1.0 — DrawnOut Olympiad Submission*
