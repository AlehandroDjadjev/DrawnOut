# Frontend Image Integration Map

## Overview

This document maps the code path for JSON drawing action execution during lesson playback in `whiteboard_demo`. The goal is to identify exactly where `sketch_image` actions from the backend need to be handled.

---

## 1. Data Models

### `lib/models/timeline.dart`

| Class | Description |
|-------|-------------|
| `SyncedTimeline` | Root timeline object with `segments[]` and `totalDuration` |
| `TimelineSegment` | A segment with `speechText`, `audioFile`, and `drawingActions[]` |
| `DrawingAction` | Individual action: `type`, `text`, `level?`, `timingHint?`, `style?` |

```dart
// lines 49-83
class DrawingAction {
  final String type;  // heading, bullet, formula, label, subbullet
  final String text;
  final int? level;
  final String? timingHint;
  final Map<String, dynamic>? style;

  factory DrawingAction.fromJson(Map<String, dynamic> json) { ... }
}
```

**Current supported types**: `heading`, `bullet`, `formula`, `label`, `subbullet`

### `lib/models/image_requests.dart`

Existing image-related models (for reference):
- `ImagePlacement` — x, y, width, height, scale
- `ScriptImageRequest` — id, prompt, placement, filenameHint, style
- `ResearchedImage` — url, source, title, dimensions, license

---

## 2. JSON Parsing Flow

```
Backend Response (JSON)
       ↓
SyncedTimeline.fromJson()           [lib/models/timeline.dart:100]
       ↓
TimelineSegment.fromJson()          [lib/models/timeline.dart:21]
       ↓
DrawingAction.fromJson()            [lib/models/timeline.dart:64]
       ↓
List<DrawingAction> drawingActions
```

---

## 3. Action Execution Flow

### Entry Points

There are **two main paths** for executing drawing actions:

#### Path A: Timeline Playback (Synchronized Audio + Drawing)

```
TimelinePlaybackController._playSegment()
    [lib/controllers/timeline_playback_controller.dart:75]
       ↓
onDrawingActionsTriggered!(segment.drawingActions)
    [lib/controllers/timeline_playback_controller.dart:107]
       ↓
_handleSyncedDrawingActions(List<DrawingAction> actions)
    [lib/main.dart:1234]
       ↓
_placeBlock(...)   ← for each action
    [lib/main.dart:1281-1290]
```

#### Path B: Manual/Planner Rendering (Non-synchronized)

```
_runPlannerAndRender() or _handleWhiteboardActions()
    [lib/main.dart:939, 906]
       ↓
_placeBlock(...)   ← for each action
    [lib/main.dart:918-926]
```

---

## 4. The Action Dispatcher: `_placeBlock()`

**File**: `lib/main.dart`  
**Lines**: 1512-1584

```dart
Future<void> _placeBlock(
  _LayoutState st, {
  required String type,      // ← action type dispatched here
  required String text,
  int level = 1,
  Map<String, dynamic>? style,
  required List<List<Offset>> accum,
  double fontScale = 1.0,
}) async { ... }
```

### Current Type Handling

| Location | What it handles |
|----------|-----------------|
| `_chooseFont()` lines 1656-1662 | Font selection by type (`heading`, `formula`, else body) |
| `_indentFor()` lines 1664-1676 | Indentation by type (`bullet`, `subbullet`) |
| Line 1569 | `preferOutline` for `heading` or `formula` |

**NOTE**: There is NO explicit switch/case. Types are handled via:
- Font selection in `_chooseFont()`
- Indentation in `_indentFor()`
- Style flags (e.g., `preferOutline`)

All types currently go through the **same text rendering pipeline**:
1. `_wrapText()` — word wrap
2. `_drawTextLines()` → `_renderTextLine()` → `Vectorizer.vectorize()`
3. Strokes accumulated in `accum`

---

## 5. Hook Point for `sketch_image`

### Where to Add Support

**Option A: Intercept in `_placeBlock()`** (Recommended)

Add early return for image types before text processing:

```dart
// lib/main.dart, inside _placeBlock(), after line 1520
if (type == 'sketch_image') {
  await _placeSketchImage(st, style: style, accum: accum);
  return;
}
```

### Required Changes

1. **Extend `DrawingAction` model** (`lib/models/timeline.dart`):
   ```dart
   class DrawingAction {
     final String type;
     final String text;
     final int? level;
     final String? timingHint;
     final Map<String, dynamic>? style;
     final String? imageUrl;      // NEW: URL for sketch_image
     final String? imageBase64;   // NEW: base64 fallback
     final Map<String, dynamic>? placement; // NEW: x, y, width, height
   }
   ```

2. **Add `_placeSketchImage()` method** (`lib/main.dart`):
   - Fetch/decode image from URL or base64
   - Calculate placement in layout
   - Vectorize image → strokes
   - Add to `accum`
   - Update `_LayoutState` cursor

3. **Reference existing diagram pipeline** (`lib/main.dart:1370-1413`):
   - `_startDiagramPipeline()` — fetches image, vectorizes, places
   - `_sketchDiagramAuto()` — handles layout positioning

---

## 6. Existing Image Pipeline (Reference)

The diagram feature already handles images similarly:

| Function | Lines | Purpose |
|----------|-------|---------|
| `_startDiagramPipeline()` | 1370-1413 | Fetch image from API, vectorize, animate |
| `_sketchDiagramAuto()` | 1416-1509 | Layout positioning, collision avoidance |
| `_fetchAndSketchDiagram()` | 693-740 | Manual diagram fetch (button-triggered) |

---

## 7. Summary: Files to Modify

| File | Change |
|------|--------|
| `lib/models/timeline.dart` | Add `imageUrl`, `imageBase64`, `placement` fields to `DrawingAction` |
| `lib/main.dart` | Add `sketch_image` branch in `_placeBlock()` or before the loop |
| `lib/main.dart` | Add `_placeSketchImage()` method (can reuse `_sketchDiagramAuto()` logic) |

---

## 8. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Backend JSON Response                       │
│  { "drawing_actions": [                                          │
│      { "type": "heading", "text": "..." },                       │
│      { "type": "sketch_image", "image_url": "...", ... },  ←NEW │
│      { "type": "bullet", "text": "..." }                         │
│  ]}                                                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              DrawingAction.fromJson()                            │
│              [lib/models/timeline.dart:64]                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│   _handleSyncedDrawingActions() or _handleWhiteboardActions()    │
│   [lib/main.dart:1234 or 906]                                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     _placeBlock()                                │
│                [lib/main.dart:1512]                              │
│                                                                  │
│   if (type == 'sketch_image') {           ← ADD THIS BRANCH     │
│       await _placeSketchImage(...);                              │
│       return;                                                    │
│   }                                                              │
│   // existing text handling below                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              _placeSketchImage() (NEW)                           │
│   - Decode image from URL/base64                                 │
│   - Calculate layout position                                    │
│   - Vectorize → strokes                                          │
│   - Add to accum                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 9. Quick Reference

### Key Functions

| Function | File:Line | Purpose |
|----------|-----------|---------|
| `DrawingAction.fromJson()` | `timeline.dart:64` | Parse action from JSON |
| `_handleSyncedDrawingActions()` | `main.dart:1234` | Timeline playback handler |
| `_handleWhiteboardActions()` | `main.dart:906` | Manual/planner handler |
| `_placeBlock()` | `main.dart:1712` | **Main dispatcher** — add `sketch_image` here |
| `_sketchImageFromUrl()` | `main.dart:1529` | ✅ **IMPLEMENTED** — Fetches, vectorizes, places images |
| `_sketchDiagramAuto()` | `main.dart:1416` | Reference for image vectorization |
| `buildProxiedImageUrl()` | `lesson_pipeline_api.dart` | ✅ **IMPLEMENTED** — CORS-safe URL proxy |

### Key Types

| Type | File | Fields |
|------|------|--------|
| `DrawingAction` | `timeline.dart` | type, text, level, timingHint, style, **imageUrl, imageBase64, placement, metadata** |
| `ImagePlacement` | `image_requests.dart` | x, y, width, height, scale |
| `_LayoutState` | `main.dart` | cursorY, blocks, config, columnIndex |

---

## 10. Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| `DrawingAction` model | ✅ Done | Added imageUrl, imageBase64, placement, metadata fields |
| `buildProxiedImageUrl()` | ✅ Done | CORS proxy helper in `LessonPipelineApi` |
| `_sketchImageFromUrl()` | ✅ Done | Image fetch → vectorize → place pipeline |
| Wire up in handlers | ✅ Done | `sketch_image` branch added to both handlers |

---

## 11. Handler Integration Details

### `_handleWhiteboardActions()` (line 906)

Handles manual/planner-triggered actions. Added `sketch_image` branch:

```dart
if (type == 'sketch_image') {
  await _sketchImageFromUrl(
    imageUrl: a['image_url'],
    imageBase64: a['image_base64'],
    placement: a['placement'],
    metadata: a['metadata'],
    accum: accum,
  );
  continue;
}
```

### `_handleSyncedDrawingActions()` (line 1254)

Handles timeline playback (synced with audio). Added `sketch_image` branch:

```dart
if (action.isSketchImage) {
  await _sketchImageFromUrl(
    imageUrl: action.imageUrl,
    imageBase64: action.imageBase64,
    placement: action.placement,
    metadata: action.metadata,
    accum: accum,
  );
  continue;
}
```

### Duration Adjustment

For synced playback, image actions add ~3s per image to the draw duration to ensure smooth animation timing.

---

## 12. Debug Testing (No Backend Required)

In debug mode (`kDebugMode`), a debug panel appears in the right sidebar under "Source":

### Debug Buttons

| Button | Method | Description |
|--------|--------|-------------|
| **Auto-Place** | `_debugInjectSketchImage()` | Injects heading + sketch_image + bullet with auto-placement |
| **Positioned** | `_debugInjectSketchImageWithPlacement()` | Injects sketch_image with explicit x/y coordinates |

### Test Images Used

- `https://picsum.photos/400/300` — Random placeholder image
- `https://via.placeholder.com/400x300/...` — Colored placeholder
- `https://placehold.co/400x300/...` — Alternative placeholder

### How to Test

1. Run the app in debug mode: `flutter run`
2. Look for the orange **DEBUG: sketch_image** box in the right panel
3. Click **Auto-Place** to test auto-positioning
4. Click **Positioned** to test explicit coordinates
5. Watch the console for debug output showing the pipeline stages

### Removing Debug Code

The debug code is guarded by `kDebugMode` and will not appear in release builds. To remove entirely:
- Delete the `if (kDebugMode) ...[]` block in `_buildRightPanel()`
- Delete `_debugInjectSketchImage()` and `_debugInjectSketchImageWithPlacement()` methods

---

## 13. Backend Integration Verification

### Data Flow

```
Backend API Response
       ↓
TimelineApiClient.generateTimeline() / getTimeline()
       ↓
SyncedTimeline.fromJson()
       ↓
TimelineSegment.fromJson()
       ↓
DrawingAction.fromJson()  ← parses image_url, placement, metadata
       ↓
TimelinePlaybackController._playSegment()
       ↓
onDrawingActionsTriggered!(segment.drawingActions)
       ↓
_handleSyncedDrawingActions(List<DrawingAction> actions)
       ↓
(action.isSketchImage) → _sketchImageFromUrl()
```

### Debug Logging

When backend actions are processed, the console shows:

```
📥 Received 5 drawing actions from backend:
   - heading: 1
   - bullet: 3
   - sketch_image: 1
🖼️ Found 1 sketch_image action(s):
   - ID: (no alt text)
     URL: https://example.com/image.png...
     Placement: yes, Base64 fallback: no
✍️ Drawing 4 text + 1 image actions over 11.0s
🖼️ Processing sketch_image action (synced)
🖼️ Fetching image: https://example.com/image.png
   ✅ Fetched 12345 bytes
   📐 Placement: (100, 200) size: 300x225
   ✏️ Vectorized: 42 strokes
   ✅ Added 42 strokes to accum
```

### Expected Backend JSON Format

For `sketch_image` actions, the backend should send:

```json
{
  "drawing_actions": [
    {
      "type": "sketch_image",
      "text": "",
      "image_url": "https://example.com/image.png",
      "placement": {
        "x": 100.0,
        "y": 200.0,
        "width": 300.0,
        "height": 225.0,
        "scale": 1.0
      },
      "metadata": {
        "source": "openverse",
        "filename": "diagram.png"
      }
    }
  ]
}
```

### Fallback Behavior

| Scenario | Behavior |
|----------|----------|
| `image_url` missing | Check `metadata.image_url`, then `metadata.url` |
| URL fetch fails | Try `image_base64` if provided |
| No image data available | Log warning, skip action, continue playback |
| Vectorization fails | Log error, skip action, continue playback |
| `placement` missing | Use auto-placement (centered, 40% column width) |

