# Which Flutter App Should I Use?

## Architecture (Updated 2026-02-09)

**`whiteboard_demo/` is the primary Flutter application.** All development happens here.

---

## Application Structure

### 1. `whiteboard_demo/` -- PRIMARY - Use This

**Location**: `DrawnOut/whiteboard_demo/`

**Status**: Production application with full whiteboard engine

**Features**:
- Full authentication flow (login/signup)
- Modular whiteboard engine (`lib/whiteboard/`)
- Synchronized timeline playback
- Lesson pipeline with intelligent images
- Multi-pass jitter rendering
- Layout system with collision detection
- sketch_image pipeline
- Text rendering with centerline mode
- Developer debug panel (collapsible)
- Settings page with platform-aware backend URL

**To Run**:
```bash
cd DrawnOut/whiteboard_demo
flutter run
```

**Module Structure**:
```
whiteboard_demo/lib/
├── controllers/
│   ├── whiteboard_controller.dart       # Drawing controller
│   ├── whiteboard_orchestrator.dart      # Business logic orchestrator
│   └── timeline_playback_controller.dart # Audio+drawing sync
├── models/                              # DrawableStroke, Timeline, etc.
├── pages/                               # App pages (auth, home, lessons, etc.)
├── services/                            # API clients, timing, config
├── widgets/
│   └── debug_panel.dart                 # Extracted developer panel UI
├── whiteboard/
│   ├── core/       # StrokePlan, VectorObject, PlacedImage
│   ├── painters/   # SketchPainter, CommittedPainter, WhiteboardPainter
│   ├── services/   # StrokeService, TextSketchService, ImageSketchService
│   ├── text/       # FontConfig, TextLayout, CenterlineConfig
│   ├── layout/     # LayoutState, LayoutConfig, collision detection
│   └── widgets/    # SketchPlayer
├── main.dart                            # App entry point + developer whiteboard UI
└── vectorizer.dart                      # Platform conditional imports
```

---

### 2. `frontend/` -- ARCHIVED

**Location**: `DrawnOut/frontend/`

**Status**: Archived. Was previously the production target, but development has consolidated into `whiteboard_demo/`.

**Note**: Contains a parallel copy of the whiteboard module that may be useful as reference, but do not add new features here.

---

### 3. `visual_whiteboard/` -- ARCHIVED - Algorithm Reference

**Location**: Was in `DrawnOut/visual_whiteboard/` (may no longer exist)

**Unique Features** (documented for reference):
- Curvature-based timing algorithms
- Travel time calculation between strokes
- Cost-based animation progress
- Step-mode debugging

These algorithms are documented in `readmes/UNIQUE_FEATURES.md`.

---

## Quick Decision Tree

```
Need whiteboard functionality?
    |
    +---> Building/extending features?
    |       +---> Use whiteboard_demo/
    |
    +---> Debugging vectorization parameters?
    |       +---> Use whiteboard_demo/ developer panel
    |
    +---> Need advanced timing algorithms?
            +---> Reference readmes/UNIQUE_FEATURES.md
```

---

## Development Guidelines

### For New Features

1. Work in `whiteboard_demo/lib/`
2. For business logic: add to `controllers/whiteboard_orchestrator.dart`
3. For UI: add to `widgets/` or relevant page
4. For drawing engine: add to `whiteboard/` module
5. Follow existing modular architecture

### For Bug Fixes

1. Fix in `whiteboard_demo/` 
2. Document behavioral changes
3. Update tests if applicable

### Android Emulator

The app auto-detects Android emulator and uses `10.0.2.2` instead of `localhost` to reach the host backend. See `services/app_config_service.dart`.

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| `WHITEBOARD_COMPARISON.md` | Detailed feature comparison |
| `UNIQUE_FEATURES.md` | Features exclusive to each app |
| `API_DEPENDENCY_MAP.md` | Backend endpoint usage |
| `FEATURE_PARITY_CHECKLIST.md` | Migration status checklist |

---*Last updated: 2026-02-09*  
*Architecture: Primary app is whiteboard_demo/*