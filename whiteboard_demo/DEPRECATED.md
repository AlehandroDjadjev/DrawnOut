# whiteboard_demo/ — Primary Application

**Status**: This is the **primary** Flutter application for DrawnOut.

---

## Architecture (Updated 2026-02-09)

This application was previously labeled as a demo/reference, but is now the canonical source for all whiteboard functionality.

## Modular Structure

The codebase has been modularized into:

### Controllers (`lib/controllers/`)
- `whiteboard_orchestrator.dart` — Business logic for vectorization, layout, content rendering
- `whiteboard_controller.dart` — Drawing state management
- `timeline_playback_controller.dart` — Audio + drawing synchronization

### Whiteboard Engine (`lib/whiteboard/`)
- `core/` — StrokePlan, VectorObject, PlacedImage
- `painters/` — SketchPainter, CommittedPainter, WhiteboardPainter
- `services/` — StrokeService, TextSketchService, ImageSketchService
- `text/` — FontConfig, TextLayoutService, CenterlineConfig
- `layout/` — LayoutState, LayoutConfig, collision detection

### Widgets (`lib/widgets/`)
- `debug_panel.dart` — Developer control panel (extracted from main.dart)

### Services (`lib/services/`)
- API clients (lesson, timeline, backend)
- App configuration
- Stroke timing and building

---

## Running

```bash
cd DrawnOut/whiteboard_demo
flutter run
```

For Android emulator, the app automatically uses `10.0.2.2` for backend connectivity.

---

*Updated: 2026-02-09*
