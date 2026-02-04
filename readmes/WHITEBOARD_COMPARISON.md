# Whiteboard Implementation Comparison

**Purpose**: Document the drawing capabilities of each whiteboard implementation to guide the unification effort.

---

## Overview

| Aspect | `frontend/lib/whiteboard/` | `whiteboard_demo/lib/main.dart` | `visual_whiteboard/lib/main.dart` |
|--------|---------------------------|--------------------------------|----------------------------------|
| **Lines of Code** | ~650 (controller) + modules | ~3385 (monolithic) | ~2367 (monolithic) |
| **Architecture** | Modular (services, controllers, models) | Single file with classes | Single file with inline classes |
| **Primary Purpose** | Production app with auth | Demo/prototype with full features | Vector animation viewer |
| **Maintenance Status** | Active, production target | Active, feature-rich prototype | Reference/archive |
| **Web Compatible** | Yes (conditional imports) | Partial (dart:io usage) | No (dart:io) |

---

## 1. `frontend/lib/whiteboard/`

### File Structure

```
frontend/lib/whiteboard/
├── whiteboard.dart              # Library barrel export
├── controllers/
│   ├── whiteboard_controller.dart     # Main state management (648 lines)
│   └── timeline_playback_controller.dart  # Audio + drawing sync
├── models/
│   ├── drawable_stroke.dart     # Stroke with timing metadata
│   ├── stroke_types.dart        # StrokePolyline, StrokeCubic
│   └── timeline.dart            # SyncedTimeline, DrawingAction
├── painters/
│   └── whiteboard_painter.dart  # Custom Flutter painter
└── services/
    ├── stroke_builder_service.dart    # Converts raw → drawable
    ├── stroke_timing_service.dart     # Computes animation timing
    ├── whiteboard_backend_service.dart # Backend CRUD (disabled)
    ├── timeline_api_service.dart      # Timeline API client
    ├── lesson_api_service.dart        # Lesson API client
    ├── vectorizer.dart                # Conditional import stub
    ├── vectorizer_web.dart            # OpenCV.js for web
    └── vectorizer_native.dart         # Native vectorization
```

### Capabilities

#### Drawing Engine
- **Stroke types**: Polyline and Cubic Bezier support
- **DrawableStroke**: Rich metadata (timing, curvature, bounds, grouping)
- **Wobble effect**: Hand-drawn variation in `stroke_builder_service.dart`
- **Animation**: AnimationController-based with cost-based progress

#### Text Rendering
- **Local rendering**: TextPainter → PNG → Vectorize pipeline
- **Centerline mode**: Basic support (hardcoded 80px threshold)
- **Stroke stitching**: `_stitchStrokes()` in controller
- **Direction normalization**: Left-to-right stroke ordering

#### Timeline Integration
- **TimelinePlaybackController**: Audio sync with just_audio
- **DrawingAction handling**: heading, bullet, subbullet, label, formula
- **sketch_image**: Placeholder only (logs, doesn't render)

#### API Integration
- **TimelineApiService**: Generate and fetch timelines
- **LessonApiService**: Start lessons, get sessions
- **WhiteboardBackendService**: CRUD for objects (currently disabled)

#### Platform Support
- **Web**: Conditional imports for vectorizer
- **Native**: Full support

### Limitations
- No layout system (collision detection, columns)
- No word wrapping
- No font size mapping by action type
- No sketch_image rendering
- No multi-pass rendering
- Basic centerline configuration

---

## 2. `whiteboard_demo/lib/main.dart`

### Key Classes (embedded in single file)

| Class/Structure | Lines | Purpose |
|-----------------|-------|---------|
| `StrokePlan` | 108-159 | Stroke collection with path operations |
| `VectorObject` | 162-180 | Committed vector with style |
| `PlacedImage` | 98-106 | Raster image with world position |
| `SketchPlayer` | 182-291 | Widget for animated stroke playback |
| `_SketchPainter` | 293-388 | Multi-pass jitter rendering |
| `_CommittedPainter` | 392-468 | Renders committed objects |
| `_RasterOnlyPainter` | 3222-3247 | Raster image only rendering |
| `_LayoutState` | 3324-3383 | Layout tracking (cursor, blocks, columns) |
| `_LayoutConfig` | 3256-3271 | Layout configuration container |
| `_BBox` | 3301-3313 | Bounding box with intersection |
| `_DrawnBlock` | 3315-3322 | Placed content block |

### Capabilities

#### Drawing Engine
- **StrokePlan**: Stroke collection with length calculation, path conversion
- **Stroke filtering**: `_filterDiagramStrokes()` removes tiny/decorative strokes
- **Multi-pass rendering**: Configurable passes with opacity and jitter
- **Jitter effect**: `jitterAmp` and `jitterFreq` for hand-drawn look

#### Text Rendering
- **Full pipeline**: `_renderTextLine()` → `Vectorizer.vectorize()` → strokes
- **Centerline mode**: Configurable via `_clThreshold`, `_clEpsilon`, etc.
- **Prefer outline headings**: Option to use outline for headings
- **Word wrapping**: `_wrapText()` with character width heuristics
- **Font mapping**: `_chooseFont()` maps action type to font size
- **Indentation**: `_indentFor()` calculates indent by bullet level
- **Stroke stitching**: `_stitchStrokes()` closes gaps

#### Layout System
- **LayoutState**: Tracks cursor position, drawn blocks, section count
- **Multi-column**: `_Columns` configuration for side-by-side content
- **Collision detection**: `_nextNonCollidingY()` prevents overlaps
- **Bounding boxes**: `_BBox` with intersection testing
- **Block placement**: `_placeBlock()` handles all action types

#### Timeline Integration
- **TimelinePlaybackController**: Full integration with callbacks
- **Dictation detection**: Short text + long audio → slow pace (85%)
- **Formula timing**: Detected via character count vs audio duration
- **Animation end tracking**: `_currentAnimEnd`, `_diagramAnimEnd`
- **Segment advance gating**: `_canAdvanceSegment()` waits for animation

#### Image Handling
- **sketch_image pipeline**: `_sketchImageFromUrl()` full implementation
- **URL resolution**: Fallbacks through metadata fields
- **CORS proxy**: `buildProxiedImageUrl()` for cross-origin
- **Base64 fallback**: If URL fetch fails
- **Auto-placement**: Centers in column if no explicit position
- **Collision avoidance**: Checks against existing blocks

#### Diagram Generation
- **Diagram API**: Calls `/api/lessons/diagram/` endpoint
- **Diagram filtering**: Removes decorative strokes
- **Auto-placement**: `_sketchDiagramAuto()` with collision detection

#### Raster Support
- **PlacedImage**: Holds decoded ui.Image with world position
- **Raster painter**: `_RasterOnlyPainter` for underlay
- **Show/hide toggle**: `_showRaster` flag

#### API Integration
- **AssistantApiClient**: Lesson sessions, segments, raise hand
- **TimelineApiClient**: Timeline generation
- **LessonPipelineApi**: Full lesson pipeline with images
- **WhiteboardPlanner**: Plans whiteboard actions

#### Debug Features
- **Extensive parameter sliders**: Vectorization, timing, style
- **Debug injection**: `_debugInjectSketchImage()` for testing
- **Console logging**: Detailed debug output

### Limitations
- Monolithic single file (difficult to maintain)
- Some dart:io usage (web compatibility issues)
- No Bezier cubic support
- Tight coupling between components

---

## 3. `visual_whiteboard/lib/main.dart`

### Key Classes (embedded in single file)

| Class/Structure | Lines | Purpose |
|-----------------|-------|---------|
| `DrawableStroke` | ~100-200 | Stroke with timing and geometry |
| `TwoPaneCanvas` | ~200+ | Main widget with two-pane layout |
| Timing system | ~400-600 | Advanced timing calculations |

### Capabilities

#### Drawing Engine
- **Polyline and Bezier**: Both formats supported
- **Wobble effect**: Sinusoidal wobble for organic look
- **Adaptive sampling**: Downsamples based on scale

#### Advanced Timing (Unique Features)
- **Curvature-based timing**: Slower at high-curvature points
- **Travel time**: Pause between strokes based on distance
- **Cost-based progress**: Uses cumulative cost for smooth animation
- **Length factor**: Timing scales with stroke length
- **Configurable bounds**: Min/max stroke time limits
- **Global speed multiplier**: Overall playback speed control
- **Curvature profile**: Local slowdowns within strokes

#### Animation
- **Step mode**: Debug stroke-by-stroke playback
- **Play/pause/replay**: Full playback controls
- **Real-time parameter adjustment**: Sliders update live

#### Backend Integration
- **Object sync**: Creates/deletes via backend API
- **Font glyphs**: Loads from `/api/wb/generate/font/` endpoint
- **Image loading**: Fetches vector JSON from backend

#### UI Features
- **Two-pane layout**: Drawing surface + control panel
- **Extensive sliders**: All timing parameters adjustable
- **Object management**: Add/erase individual objects

### Limitations
- No local text rendering (relies on backend)
- No timeline/audio sync
- No layout system
- No lesson integration
- Uses dart:io (not web compatible)
- Specialized viewer, not production app

---

## Architecture Comparison

### Modularity

```
frontend/                    whiteboard_demo/           visual_whiteboard/
├── Models ✅               ├── All in main.dart ❌    ├── All in main.dart ❌
├── Services ✅             │                          │
├── Controllers ✅          │                          │
├── Painters ✅             │                          │
└── Barrel export ✅        │                          │
```

### Dependency Flow

**frontend/**:
```
Page → Controller → Services (Timing, Builder, Backend)
         ↓
      Painter ← Models (DrawableStroke, StrokePolyline)
```

**whiteboard_demo/**:
```
_WhiteboardPageState (everything embedded)
    ├── Vectorizer
    ├── API clients (inline)
    ├── Painters (inline classes)
    └── Layout system (inline classes)
```

**visual_whiteboard/**:
```
TwoPaneCanvas (everything embedded)
    ├── Backend HTTP calls (inline)
    ├── Timing calculations (inline)
    └── Rendering (inline)
```

---

## Feature Matrix

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ |
|---------|:---------:|:----------------:|:------------------:|
| Modular architecture | ✅ | ❌ | ❌ |
| Web compatible | ✅ | 🔶 | ❌ |
| Auth integration | ✅ | ✅ | ❌ |
| Polyline strokes | ✅ | ✅ | ✅ |
| Bezier strokes | ✅ | ❌ | ✅ |
| Multi-pass rendering | ❌ | ✅ | ✅ |
| Jitter/wobble | ✅ | ✅ | ✅ |
| Local text rendering | ✅ | ✅ | ❌ |
| Centerline mode (configurable) | 🔶 | ✅ | ❌ |
| Word wrapping | ❌ | ✅ | ❌ |
| Layout system | ❌ | ✅ | ❌ |
| Collision detection | ❌ | ✅ | ❌ |
| Multi-column | ❌ | ✅ | ❌ |
| Timeline sync | ✅ | ✅ | ❌ |
| Dictation detection | ❌ | ✅ | ❌ |
| sketch_image | ❌ | ✅ | ❌ |
| Diagram generation | ❌ | ✅ | ❌ |
| Raster underlay | ❌ | ✅ | ❌ |
| Curvature timing | ❌ | ❌ | ✅ |
| Travel time | ❌ | ❌ | ✅ |
| Step mode debug | ❌ | ❌ | ✅ |
| Debug sliders | ❌ | ✅ | ✅ |
| Backend object sync | ✅ | ❌ | ✅ |

---

## Recommendation

### Primary Merge Target: `frontend/lib/whiteboard/`

**Rationale**:
1. Already has modular architecture
2. Web compatible with conditional imports
3. Has auth integration and production routing
4. Clean separation of concerns
5. Easier to extend and maintain

### Features to Port:

**From whiteboard_demo/** (Critical):
1. Layout system (`_LayoutState`, `_BBox`, collision detection)
2. Text rendering enhancements (word wrap, font mapping, indentation)
3. sketch_image pipeline
4. Dictation detection and formula timing
5. Multi-pass jitter rendering

**From visual_whiteboard/** (Nice-to-have):
1. Curvature-based timing algorithms
2. Travel time calculation
3. Step mode debugging

### Migration Strategy

1. Extract classes from whiteboard_demo into `frontend/lib/whiteboard/`
2. Create new modules: `layout/`, `text/`, `image/`
3. Port functionality incrementally, testing each feature
4. Maintain API compatibility with existing frontend integration
5. Archive whiteboard_demo and visual_whiteboard when complete

---

*Last updated: 2026-01-29*  
*Related: FEATURE_PARITY_CHECKLIST.md, API_DEPENDENCY_MAP.md*
