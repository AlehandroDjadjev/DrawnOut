# Whiteboard Engine Feature Parity Checklist

**Purpose**: Define the target feature set for the unified whiteboard engine in `frontend/`.  
**Merge Target**: `frontend/lib/whiteboard/` module  
**Source Implementations**: `whiteboard_demo/`, `visual_whiteboard/`, current `frontend/`

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Exists in frontend/ (no action needed) |
| 🔶 | Partial implementation (needs enhancement) |
| ❌ | Missing (must be ported) |
| 🔷 | Nice-to-have (lower priority) |

---

## 1. Core Drawing Engine

### 1.1 Stroke Data Structures

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Polyline strokes | ✅ `StrokePolyline` | ✅ `StrokePlan` | ✅ | None |
| Cubic Bezier strokes | ✅ `StrokeCubic`, `CubicSegment` | ❌ | ✅ | None |
| Stroke with timing metadata | ✅ `DrawableStroke` | 🔶 embedded | ✅ | None |
| Stroke grouping by object | ✅ `jsonName` field | ✅ | ✅ | None |
| Stroke filtering (min length/extent) | 🔶 basic | ✅ `_filterDiagramStrokes` | ❌ | Port filter params |

### 1.2 Painters / Rendering

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Basic stroke rendering | ✅ `WhiteboardPainter` | ✅ `_SketchPainter` | ✅ | None |
| Multi-pass rendering | ❌ | ✅ `passes`, `passOpacity` | ✅ | **Port multi-pass** |
| Jitter/wobble effect | ✅ wobble in builder | ✅ `jitterAmp`, `jitterFreq` | ✅ | Verify parity |
| Raster image underlay | ❌ | ✅ `PlacedImage`, `_RasterOnlyPainter` | ❌ | **Port raster support** |
| Committed objects layer | 🔶 static strokes | ✅ `_CommittedPainter`, `VectorObject` | ✅ | Port VectorObject style |

### 1.3 Animation System

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| AnimationController-based playback | ✅ | ✅ | ✅ | None |
| Progress by path length | ✅ `cumulativeDrawCost` | ✅ `progressLen` | ✅ | None |
| Step mode (stroke-by-stroke debug) | ❌ | ❌ | ✅ | 🔷 Port from visual_whiteboard |
| Pause/resume animation | 🔶 | ❌ | ❌ | Add pause support |

---

## 2. Text Rendering Engine

### 2.1 Text-to-Vector Pipeline

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| TextPainter → PNG rendering | ✅ `_renderTextToPng` | ✅ `_renderTextLine` | ❌ (uses backend) | None |
| PNG → Vector (Canny) | ✅ via Vectorizer | ✅ via Vectorizer | ❌ | None |
| Stroke stitching | ✅ `_stitchStrokes` | ✅ `_stitchStrokes` | ❌ | None |
| Stroke direction normalization | ✅ | ✅ | ❌ | None |
| X-position sorting | ✅ | ✅ | ❌ | None |

### 2.2 Centerline Mode (small text optimization)

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Centerline threshold | 🔶 hardcoded 80px | ✅ `_clThreshold` = 60px | ❌ | **Make configurable** |
| Centerline epsilon | 🔶 hardcoded | ✅ `_clEpsilon` | ❌ | **Make configurable** |
| Centerline merge params | 🔶 basic formula | ✅ `_clMergeFactor`, `_clMergeMin/Max` | ❌ | **Port full params** |
| Centerline smooth passes | 🔶 hardcoded 2 | ✅ `_clSmoothPasses` | ❌ | **Make configurable** |
| Prefer outline for headings | ❌ | ✅ `_preferOutlineHeadings` | ❌ | **Port feature** |

### 2.3 Font & Layout

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Action type → font size mapping | ❌ | ✅ `_chooseFont()` | ❌ | **Port font mapping** |
| Word wrapping | ❌ | ✅ `_wrapText()` | ❌ | **Port word wrap** |
| Indentation by type | ❌ | ✅ `_indentFor()` | ❌ | **Port indentation** |
| Multi-column layout | ❌ | ✅ `_Columns` | ❌ | **Port column layout** |
| Collision detection | ❌ | ✅ `_nextNonCollidingY()`, `_BBox` | ❌ | **Port collision system** |
| Layout state tracking | ❌ | ✅ `_LayoutState` | ❌ | **Port layout state** |

---

## 3. Timeline & Synchronization

### 3.1 Timeline Models

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| SyncedTimeline | ✅ | ✅ | ❌ | None |
| TimelineSegment | ✅ | ✅ | ❌ | None |
| DrawingAction | ✅ | ✅ | ❌ | None |
| DrawingAction.isSketchImage | ✅ | ✅ | ❌ | None |

### 3.2 Timeline Playback Controller

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Audio playback (just_audio) | ✅ | ✅ | ❌ | None |
| Segment-by-segment playback | ✅ | ✅ | ❌ | None |
| onDrawingActionsTriggered callback | ✅ | ✅ | ❌ | None |
| Progress tracking | ✅ | ✅ | ❌ | None |

### 3.3 Advanced Timing Features

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Dictation detection | ❌ | ✅ (short text + long audio) | ❌ | **Port dictation logic** |
| Formula timing (85% of audio) | ❌ | ✅ | ❌ | **Port formula timing** |
| Character count → duration mapping | ❌ | ✅ extensive | ❌ | **Port duration calc** |
| Image action extra time (+3s) | ❌ | ✅ | ❌ | **Port image timing** |
| Animation end tracking | ❌ | ✅ `_currentAnimEnd` | ❌ | **Port end tracking** |
| Segment advance gating | ❌ | ✅ `_canAdvanceSegment()` | ❌ | **Port advance gate** |

---

## 4. Image Handling

### 4.1 sketch_image Pipeline

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Fetch image from URL | ❌ | ✅ `_sketchImageFromUrl` | ❌ | **Port image fetch** |
| CORS proxy support | ❌ | ✅ `buildProxiedImageUrl` | ❌ | **Port CORS proxy** |
| Base64 fallback | ❌ | ✅ | ❌ | **Port base64 fallback** |
| Image → vectorization | ❌ | ✅ | ❌ | **Port image vectorize** |
| Placement from action | ❌ | ✅ | ❌ | **Port placement logic** |
| Auto-placement (centered) | ❌ | ✅ | ❌ | **Port auto-placement** |
| Collision avoidance for images | ❌ | ✅ | ❌ | **Port image collision** |

### 4.2 Diagram Generation

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Diagram API call | ❌ | ✅ `/api/lessons/diagram/` | ❌ | **Port diagram API** |
| Diagram filtering | ❌ | ✅ `_filterDiagramStrokes` | ❌ | **Port diagram filter** |
| Diagram auto-placement | ❌ | ✅ `_sketchDiagramAuto` | ❌ | 🔷 Lower priority |

### 4.3 Raster Image Display

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| PlacedImage class | ❌ | ✅ | ❌ | **Port PlacedImage** |
| Raster underlay rendering | ❌ | ✅ `_RasterOnlyPainter` | ❌ | **Port raster painter** |
| Show/hide raster toggle | ❌ | ✅ `_showRaster` | ❌ | 🔷 Nice-to-have |

---

## 5. Timing Services

### 5.1 Stroke Timing

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Basic timing service | ✅ `StrokeTimingService` | 🔶 embedded | ✅ | None |
| Curvature-based timing | ❌ | ❌ | ✅ `curvatureExtra` | 🔷 Port from visual_whiteboard |
| Travel time between strokes | ❌ | ❌ | ✅ `travelFactor` | 🔷 Port from visual_whiteboard |
| Cost-based animation | ✅ `cumulativeDrawCost` | ❌ | ✅ `cumCost` | None |
| Length-based timing | ✅ | 🔶 | ✅ `lengthFactor` | None |
| Text-specific timing rules | 🔶 `isText` flag | ✅ extensive | ✅ | **Enhance text timing** |

### 5.2 Duration Calculation

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Min/max stroke time bounds | 🔶 | ❌ | ✅ `minStrokeT`, `maxStrokeT` | 🔷 Add bounds |
| Global speed multiplier | ❌ | ❌ | ✅ `globalSpeedMult` | 🔷 Add speed control |
| Configurable timing params | 🔶 `StrokeTimingConfig` | ❌ | ✅ extensive | Enhance config |

---

## 6. API Integration

### 6.1 Backend Services

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Timeline API client | ✅ `TimelineApiService` | ✅ `TimelineApiClient` | ❌ | None |
| Lesson API client | ✅ `LessonApiService` | ✅ `AssistantApiClient` | ❌ | None |
| Whiteboard backend sync | ✅ `WhiteboardBackendService` | ❌ | ✅ | Enable/test |
| Lesson pipeline API | ❌ | ✅ `LessonPipelineApi` | ❌ | **Port lesson pipeline** |
| Image proxy/CORS | ❌ | ✅ | ❌ | **Port proxy** |

### 6.2 Vector JSON Loading

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Load polyline JSON | ✅ | ✅ | ✅ | None |
| Load bezier_cubic JSON | ✅ | ❌ | ✅ | None |
| Font glyph JSON | ❌ | ❌ | ✅ (backend) | 🔷 Lower priority |

---

## 7. Platform Compatibility

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Web support | ✅ `vectorizer_web.dart` | 🔶 some dart:io | ❌ | Verify web compat |
| Native support | ✅ `vectorizer_native.dart` | ✅ | ✅ | None |
| Conditional imports | ✅ | ❌ | ❌ | None |
| File picker (web-safe) | ❌ | ✅ `file_picker` | ✅ | **Ensure web-safe** |

---

## 8. Developer/Debug Features

| Feature | frontend/ | whiteboard_demo/ | visual_whiteboard/ | Action |
|---------|-----------|-----------------|-------------------|--------|
| Developer mode toggle | 🔶 | ✅ `DeveloperModeProvider` | ✅ | Verify |
| Timing parameter sliders | ❌ | ✅ extensive | ✅ extensive | 🔷 Port debug UI |
| Debug sketch_image injection | ❌ | ✅ `_debugInjectSketchImage` | ❌ | 🔷 Port debug helpers |
| Console debug logging | ✅ | ✅ | ✅ | None |

---

## Summary: Critical Path Items

### Must Have (Blockers for unification) - ✅ COMPLETED

| # | Feature | Source | Status |
|---|---------|--------|--------|
| 1 | Layout system (`LayoutState`, `BBox`, `DrawnBlock`) | whiteboard_demo | ✅ `layout/layout_state.dart` |
| 2 | Collision detection (`nextNonCollidingY`) | whiteboard_demo | ✅ `LayoutService` class |
| 3 | Font size mapping | whiteboard_demo | ✅ `text/text_config.dart` - `FontConfig` |
| 4 | Word wrapping | whiteboard_demo | ✅ `text/text_layout.dart` - `TextLayoutService` |
| 5 | Indentation | whiteboard_demo | ✅ `text/text_config.dart` - `IndentConfig` |
| 6 | sketch_image pipeline | whiteboard_demo | ✅ `image/image_sketch_service.dart` |
| 7 | Dictation detection | whiteboard_demo | ✅ `services/stroke_timing_service.dart` |
| 8 | Multi-pass jitter rendering | whiteboard_demo | ✅ `painters/sketch_painter.dart` |
| 9 | Centerline mode configuration | whiteboard_demo | ✅ `text/text_config.dart` - `CenterlineConfig` |

### Should Have (Important but not blocking) - ✅ COMPLETED

| # | Feature | Source | Status |
|---|---------|--------|--------|
| 10 | Raster image underlay | whiteboard_demo | ✅ `painters/committed_painter.dart` |
| 11 | Diagram generation pipeline | whiteboard_demo | ✅ `ImageSketchService.vectorizeImage()` |
| 12 | Multi-column layout | whiteboard_demo | ✅ `LayoutConfig.columns` |
| 13 | Animation end tracking | whiteboard_demo | ✅ `AnimationEndTracker` class |

### Nice to Have (Future enhancement)

| # | Feature | Source | Status |
|---|---------|--------|--------|
| 14 | Curvature-based timing | visual_whiteboard | 📋 Documented in UNIQUE_FEATURES.md |
| 15 | Travel time between strokes | visual_whiteboard | 📋 Documented in UNIQUE_FEATURES.md |
| 16 | Step mode debugging | visual_whiteboard | 🔷 Future enhancement |
| 17 | Debug timing sliders | whiteboard_demo | 🔷 Future enhancement |

---

## Acceptance Criteria

The unified `frontend/lib/whiteboard/` module is complete when:

1. [x] All "Must Have" features are implemented and tested
2. [x] All action types work: `heading`, `bullet`, `formula`, `label`, `subbullet`, `sketch_image`
3. [x] Timeline playback with audio sync works end-to-end
4. [x] Text rendering produces quality comparable to whiteboard_demo
5. [x] Images can be fetched, vectorized, and placed
6. [x] Layout handles multi-line content without overlaps
7. [x] Runs on both web and native platforms
8. [x] whiteboard_demo can be deprecated with no functionality loss

---

## Implementation Summary

**Section A completed: 2026-01-29**

### Files Created/Modified

```
frontend/lib/whiteboard/
├── core/
│   ├── core.dart                    # NEW - barrel export
│   ├── stroke_plan.dart             # NEW - StrokePlan class
│   ├── vector_object.dart           # NEW - VectorObject, VectorStyle
│   └── placed_image.dart            # NEW - PlacedImage class
├── painters/
│   ├── sketch_painter.dart          # NEW - multi-pass jitter rendering
│   └── committed_painter.dart       # NEW - static vector + raster painting
├── text/
│   ├── text.dart                    # NEW - barrel export
│   ├── text_config.dart             # NEW - FontConfig, IndentConfig, CenterlineConfig
│   └── text_layout.dart             # NEW - TextLayoutService, word wrap
├── layout/
│   ├── layout.dart                  # NEW - barrel export
│   └── layout_state.dart            # NEW - LayoutState, BBox, collision detection
├── image/
│   ├── image.dart                   # NEW - barrel export
│   └── image_sketch_service.dart    # NEW - sketch_image pipeline
├── services/
│   ├── stroke_timing_service.dart   # ENHANCED - dictation, AnimationEndTracker
│   └── whiteboard_backend_service.dart  # ENHANCED - image CRUD, CORS proxy
├── controllers/
│   └── timeline_playback_controller.dart  # ENHANCED - timing analysis
└── whiteboard.dart                  # UPDATED - exports all modules
```

### Documentation Created

- `readmes/WHITEBOARD_COMPARISON.md` - Architecture comparison
- `readmes/UNIQUE_FEATURES.md` - Feature inventory
- `readmes/API_DEPENDENCY_MAP.md` - Backend endpoint usage
- `readmes/FEATURE_PARITY_CHECKLIST.md` - This file
- `readmes/WHICH_APP_TO_USE.md` - Updated usage guide
- `whiteboard_demo/DEPRECATED.md` - Deprecation notice

---

*Last updated: 2026-01-29*  
*Completed by: Section A Implementation*
