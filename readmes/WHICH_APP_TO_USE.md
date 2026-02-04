# Which Flutter App Should I Use?

## 🎯 Unified Architecture (2026-01-29)

The whiteboard functionality has been **unified** into the `frontend/` application. Use this as the primary development target.

---

## Application Structure

### 1. `frontend/` ✅ **PRIMARY - Use This**

**Location**: `DrawnOut/frontend/`

**Status**: Production application with unified whiteboard engine

**Features**:
- ✅ Full authentication flow (login/signup)
- ✅ Modular whiteboard engine (`lib/whiteboard/`)
- ✅ Synchronized timeline playback
- ✅ Dictation detection for formula segments
- ✅ Multi-pass jitter rendering
- ✅ Layout system with collision detection
- ✅ sketch_image pipeline
- ✅ Text rendering with centerline mode
- ✅ Web platform support

**To Run**:
```bash
cd DrawnOut/frontend
flutter run -d chrome
```

**Whiteboard Module Structure**:
```
frontend/lib/whiteboard/
├── core/           # StrokePlan, VectorObject, PlacedImage
├── models/         # DrawableStroke, Timeline, StrokeTypes
├── painters/       # SketchPainter, CommittedPainter, WhiteboardPainter
├── services/       # Timing, Vectorizer, API clients
├── text/           # FontConfig, TextLayout, CenterlineConfig
├── layout/         # LayoutState, collision detection
├── image/          # ImageSketchService
├── controllers/    # WhiteboardController, TimelinePlaybackController
└── whiteboard.dart # Barrel export
```

---

### 2. `whiteboard_demo/` ⚠️ **DEPRECATED - Reference Only**

**Location**: `DrawnOut/whiteboard_demo/`

**Status**: Deprecated - preserved as reference implementation

**Use For**:
- Historical reference
- Debug UI controls (vectorization sliders)
- Testing parameter adjustments
- Comparing behavior

**Do NOT**:
- Add new features here
- Use for production development
- Consider this the canonical source

**To Run** (for reference):
```bash
cd DrawnOut/whiteboard_demo
flutter run -d chrome
```

See `whiteboard_demo/DEPRECATED.md` for details on what was extracted.

---

### 3. `visual_whiteboard/` 📦 **ARCHIVED - Algorithm Reference**

**Location**: `DrawnOut/visual_whiteboard/`

**Status**: Archived - specialized timing algorithms preserved

**Unique Features** (worth referencing):
- Curvature-based timing algorithms
- Travel time calculation between strokes
- Cost-based animation progress
- Step-mode debugging

These algorithms have been documented in `readmes/UNIQUE_FEATURES.md` and can be ported to `frontend/` if needed.

---

## Quick Decision Tree

```
Need whiteboard functionality?
    │
    ├─→ Building/extending features? 
    │       └─→ Use frontend/lib/whiteboard/
    │
    ├─→ Debugging vectorization parameters?
    │       └─→ Run whiteboard_demo/ temporarily
    │
    └─→ Need advanced timing algorithms?
            └─→ Reference visual_whiteboard/
```

---

## Development Guidelines

### For New Features

1. Work in `frontend/lib/whiteboard/`
2. Follow the modular architecture
3. Add exports to `whiteboard.dart`
4. Check `FEATURE_PARITY_CHECKLIST.md` for remaining work

### For Bug Fixes

1. Fix in `frontend/` first
2. Document if behavior differs from whiteboard_demo/
3. Update tests

### For Testing

1. Run `frontend/` app
2. Use whiteboard_demo/ only if debugging vectorization
3. Compare outputs if behavior differs

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| `WHITEBOARD_COMPARISON.md` | Detailed feature comparison |
| `UNIQUE_FEATURES.md` | Features exclusive to each app |
| `API_DEPENDENCY_MAP.md` | Backend endpoint usage |
| `FEATURE_PARITY_CHECKLIST.md` | Migration status checklist |
| `whiteboard_demo/DEPRECATED.md` | Deprecation details |

---*Last updated: 2026-01-29*  
*Architecture: Unified whiteboard engine in frontend/*