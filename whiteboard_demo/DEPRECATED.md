# ⚠️ DEPRECATED - Reference Implementation

**Status**: This application is now a **reference/archive** implementation.

**Canonical Source**: `frontend/lib/whiteboard/` module

---

## Migration Notice

As of 2026-01-29, the whiteboard functionality has been unified into the `frontend/` application. The `whiteboard_demo/` directory is preserved as a reference for:

1. Historical context and feature documentation
2. Advanced implementation patterns
3. Debug/development features not yet ported

---

## What Was Extracted

The following components have been extracted to `frontend/lib/whiteboard/`:

### Core Data Structures (`frontend/lib/whiteboard/core/`)
- `StrokePlan` → `stroke_plan.dart`
- `VectorObject` → `vector_object.dart`
- `PlacedImage` → `placed_image.dart`

### Painters (`frontend/lib/whiteboard/painters/`)
- `_SketchPainter` → `sketch_painter.dart` (multi-pass jitter rendering)
- `_CommittedPainter` → `committed_painter.dart`
- `_RasterOnlyPainter` → `committed_painter.dart`

### Timing Features (`frontend/lib/whiteboard/services/stroke_timing_service.dart`)
- Dictation detection logic
- Formula timing (85% of audio duration)
- Character count → duration mapping
- `AnimationEndTracker` class

### Text Rendering (`frontend/lib/whiteboard/text/`)
- `FontConfig` - Font size by action type
- `IndentConfig` - Indentation by level
- `CenterlineConfig` - Small text optimization
- `TextLayoutService` - Word wrapping, layout calculations

### Layout System (`frontend/lib/whiteboard/layout/`)
- `LayoutState` - Cursor tracking, blocks
- `LayoutConfig` - Page, columns configuration
- `BBox`, `DrawnBlock` - Collision detection
- `LayoutService` - Placement calculations

### Image Pipeline (`frontend/lib/whiteboard/image/`)
- `ImageSketchService` - sketch_image handling
- `ImageVectorConfig` - Vectorization parameters
- CORS proxy URL building

---

## What Remains Unique Here

Features still only in `whiteboard_demo/` (not yet extracted):

1. **Debug UI Controls**
   - Vectorization parameter sliders
   - Timing adjustment UI
   - Debug injection functions

2. **Full Planner Integration**
   - `WhiteboardPlanner` class
   - Diagram generation pipeline
   - `_sketchDiagramAuto()` placement

3. **Advanced Configuration**
   - Extensive runtime configuration
   - Live parameter adjustment
   - Developer mode panels

---

## For New Development

**DO NOT** add new features to this directory. Instead:

1. Work in `frontend/lib/whiteboard/` module
2. Follow the modular architecture pattern
3. Add exports to `whiteboard.dart` barrel file
4. See `readmes/FEATURE_PARITY_CHECKLIST.md` for remaining work

---

## Running This App (For Reference Only)

```bash
cd DrawnOut/whiteboard_demo
flutter run -d chrome
```

The app still works and can be used to:
- Test vectorization parameters
- Debug timing issues
- Compare behavior with frontend/ implementation

---

## Related Documentation

- `readmes/WHITEBOARD_COMPARISON.md` - Feature comparison
- `readmes/UNIQUE_FEATURES.md` - Unique features list
- `readmes/API_DEPENDENCY_MAP.md` - API dependencies
- `readmes/FEATURE_PARITY_CHECKLIST.md` - Migration checklist

---

*Deprecated: 2026-01-29*  
*Reason: Unified into frontend/lib/whiteboard/ module*
