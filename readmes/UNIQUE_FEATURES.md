# Unique Features by Implementation

**Purpose**: Identify exclusive features in each whiteboard implementation that must be preserved or ported during unification.

---

## frontend/lib/whiteboard/ — Exclusive Features

These features exist **only** in the frontend module and should be preserved:

### 1. Modular Architecture
- **Services pattern**: Separate classes for timing, building, backend sync
- **Dependency injection**: Services can be overridden via constructor
- **Barrel export**: Single `whiteboard.dart` exposes all public APIs
- **Testability**: Each component can be unit tested in isolation

### 2. Web Platform Support
- **Conditional imports**: `vectorizer.dart` switches between `_web` and `_native`
- **No dart:io dependency**: Core module avoids platform-specific code
- **OpenCV.js integration**: Web-based vectorization via `vectorizer_web.dart`

### 3. Cubic Bezier Strokes
- **StrokeCubic**: Supports bezier curves with multiple CubicSegments
- **CubicSegment**: 4-point control (p0, c1, c2, p1)
- **Bezier JSON loading**: Parses `bezier_cubic` format from backend

### 4. DrawableStroke Rich Metadata
- **Geometric properties**: length, centroid, bounds, curvature
- **Timing fields**: drawTime, travelTime, cumulativeDrawCost
- **Importance scoring**: For prioritizing stroke rendering order
- **Object association**: jsonName for grouping/erasing

### 5. Stroke Builder Service
- **Upscaling**: Targets 2000px resolution for quality
- **Wobble computation**: Applies variation based on length and curvature
- **Timing computation**: Integrates with StrokeTimingService

### 6. Production Integration
- **Auth flow integration**: Works with login/signup pages
- **Route navigation**: `/whiteboard` route in app routing
- **Provider integration**: Uses DeveloperModeProvider, ThemeProvider

---

## whiteboard_demo/lib/main.dart — Exclusive Features

These features exist **only** in whiteboard_demo and must be ported:

### 1. Layout System

#### _LayoutState Class
```dart
class _LayoutState {
  double cursorY;          // Current vertical position
  int columnIndex;         // Active column (0 or 1)
  List<_DrawnBlock> blocks; // All placed content
  int sectionCount;        // Page counter
  _LayoutConfig config;    // Layout configuration
}
```

#### Collision Detection
```dart
// Finds next Y position that doesn't overlap existing blocks
double _nextNonCollidingY(double y, double w, double h, _BBox ignore) {
  for (final block in _layout!.blocks) {
    if (block.bbox.intersects(_BBox(x1, y, x2, y + h))) {
      y = block.bbox.y2 + 12.0; // Move below with margin
    }
  }
  return y;
}
```

#### Multi-Column Support
```dart
class _Columns {
  final double leftEdge;   // Left column start
  final double gutter;     // Space between columns
  final double colW;       // Column width
}
```

### 2. Advanced Text Rendering

#### Word Wrapping
```dart
List<String> _wrapText(String text, double maxW, double charW) {
  // Splits text into lines that fit within maxW
  // Uses character width heuristic (charW) for estimation
}
```

#### Font Size Mapping
```dart
double _chooseFont(_LayoutState st, String type) {
  switch (type) {
    case 'heading': return st.config.fonts.heading;
    case 'formula': return st.config.fonts.formula;
    default: return st.config.fonts.body;
  }
}
```

#### Type-Based Indentation
```dart
double _indentFor(_LayoutState st, String type, int level) {
  switch (type) {
    case 'bullet': return st.config.indent.bullet;
    case 'subbullet': return st.config.indent.bullet + st.config.indent.sub * level;
    default: return 0.0;
  }
}
```

### 3. Centerline Mode Configuration

```dart
// Configurable parameters (not hardcoded)
double _clThreshold = 60.0;      // Font size threshold
double _clEpsilon = 0.6;         // Simplification epsilon
double _clResample = 0.8;        // Resampling spacing
double _clMergeFactor = 0.12;    // Merge distance factor
double _clMergeMin = 8.0;        // Minimum merge distance
double _clMergeMax = 24.0;       // Maximum merge distance
int _clSmoothPasses = 2;         // Smoothing iterations
bool _preferOutlineHeadings = true; // Use outline for headings
```

### 4. sketch_image Pipeline

#### Full Implementation
```dart
Future<void> _sketchImageFromUrl({
  String? imageUrl,
  String? imageBase64,
  Map<String, dynamic>? placement,
  Map<String, dynamic>? metadata,
  required List<List<Offset>> accum,
}) async {
  // 1. Resolve URL (with metadata fallbacks)
  // 2. Fetch image bytes (with CORS proxy)
  // 3. Decode and get dimensions
  // 4. Calculate placement (explicit or auto)
  // 5. Vectorize with image parameters
  // 6. Filter and transform strokes
  // 7. Update layout state
  // 8. Add strokes to accumulator
}
```

#### CORS Proxy
```dart
String buildProxiedImageUrl(String originalUrl) {
  // Routes through backend to avoid CORS issues
  return '$baseUrl/api/lesson-pipeline/image-proxy/?url=${Uri.encodeComponent(originalUrl)}';
}
```

### 5. Dictation Detection

```dart
// Detects "formula dictation" segments that need slow rendering
bool isDictation = false;
if (totalChars < 50 && segmentAudio > 5.0) {
  isDictation = true;
  drawSeconds = segmentAudio * 0.85; // Use 85% of audio duration
}
```

### 6. Animation End Tracking

```dart
DateTime? _currentAnimEnd;   // When text animation finishes
DateTime? _diagramAnimEnd;   // When diagram animation finishes

bool _canAdvanceSegment() {
  final now = DateTime.now();
  if (_currentAnimEnd != null && now.isBefore(_currentAnimEnd!)) return false;
  if (_diagramAnimEnd != null && now.isBefore(_diagramAnimEnd!)) return false;
  return true;
}
```

### 7. Multi-Pass Jitter Rendering

```dart
class _SketchPainter extends CustomPainter {
  final int passes;        // Number of render passes (default 2)
  final double passOpacity; // Opacity per pass (default 0.8)
  final double jitterAmp;   // Jitter amplitude
  final double jitterFreq;  // Jitter frequency
  
  @override
  void paint(Canvas canvas, Size size) {
    for (int pass = 0; pass < passes; pass++) {
      // Apply jitter based on pass index
      // Render with reduced opacity
    }
  }
}
```

### 8. Raster Image Support

```dart
class PlacedImage {
  final ui.Image image;     // Decoded Flutter image
  Offset worldCenter;       // Position in world coordinates
  Size worldSize;           // Size in world coordinates
}

class _RasterOnlyPainter extends CustomPainter {
  final List<PlacedImage> images;
  final Offset pan;
  final double zoom;
  // Renders raster images without strokes
}
```

### 9. Diagram Generation Pipeline

```dart
Future<void> _startDiagramPipeline(String prompt) async {
  // 1. Call /api/lessons/diagram/ with prompt
  // 2. Receive base64 image
  // 3. Vectorize with diagram parameters
  // 4. Filter decorative strokes
  // 5. Auto-place in layout
}
```

### 10. Debug Injection Functions

```dart
// For testing sketch_image without backend
void _debugInjectSketchImage() {
  _handleWhiteboardActions([
    {'type': 'heading', 'text': 'Debug Test'},
    {'type': 'sketch_image', 'image_url': 'https://picsum.photos/400/300'},
    {'type': 'bullet', 'text': 'Test complete'}
  ]);
}
```

---

## visual_whiteboard/lib/main.dart — Exclusive Features

These features exist **only** in visual_whiteboard and are worth extracting:

### 1. Curvature-Based Timing

```dart
// Adjusts stroke timing based on curvature complexity
double computeCurvatureTime(List<Offset> points) {
  double totalCurvature = 0.0;
  for (int i = 1; i < points.length - 1; i++) {
    final angle = computeAngle(points[i-1], points[i], points[i+1]);
    totalCurvature += angle.abs();
  }
  return baseTime + (totalCurvature * curvatureExtra);
}
```

### 2. Travel Time Calculation

```dart
// Computes pause between strokes based on pen travel distance
double computeTravelTime(Offset fromEnd, Offset toStart) {
  final distance = (toStart - fromEnd).distance;
  return distance * travelFactor;
}
```

### 3. Cost-Based Animation Progress

```dart
// Uses cumulative cost for smooth, consistent animation
double cumCost = 0.0;
for (final stroke in strokes) {
  cumCost += stroke.length + stroke.curvature * curvatureWeight;
  stroke.cumulativeCost = cumCost;
}

// Progress calculated by cost, not by stroke index
double getProgress(double animValue) {
  final targetCost = totalCost * animValue;
  // Find stroke at targetCost
}
```

### 4. Step Mode Debugging

```dart
// Play one stroke at a time for debugging
bool stepMode = false;
int currentStrokeIndex = 0;

void stepForward() {
  if (currentStrokeIndex < strokes.length - 1) {
    currentStrokeIndex++;
    renderUpToStroke(currentStrokeIndex);
  }
}
```

### 5. Configurable Timing Bounds

```dart
double minStrokeT = 0.1;    // Minimum time per stroke (seconds)
double maxStrokeT = 2.0;    // Maximum time per stroke (seconds)
double lengthFactor = 0.001; // Seconds per pixel of length
double curvatureExtra = 0.5; // Extra time for curved strokes
double travelFactor = 0.002; // Travel time factor
double globalSpeedMult = 1.0; // Overall speed multiplier
```

### 6. Two-Pane UI Layout

```dart
// Left pane: drawing surface (3:1 flex)
// Right pane: controls (340px fixed width)
Row(
  children: [
    Expanded(flex: 3, child: drawingSurface),
    SizedBox(width: 340, child: controlPanel),
  ],
)
```

### 7. Font Glyph Loading (Backend)

```dart
// Loads pre-vectorized font glyphs from backend
Future<List<Stroke>> loadGlyph(String char) async {
  final hex = char.codeUnitAt(0).toRadixString(16).padLeft(4, '0');
  final response = await http.get(
    Uri.parse('$baseUrl/api/wb/generate/font/$hex.json')
  );
  return parseStrokes(response.body);
}
```

---

## Porting Priority

### Critical (Must Port)

| Feature | Source | Target | Effort |
|---------|--------|--------|--------|
| Layout system | whiteboard_demo | frontend/whiteboard/layout/ | Medium |
| Collision detection | whiteboard_demo | frontend/whiteboard/layout/ | Low |
| Word wrapping | whiteboard_demo | frontend/whiteboard/text/ | Low |
| Font mapping | whiteboard_demo | frontend/whiteboard/text/ | Low |
| Indentation | whiteboard_demo | frontend/whiteboard/text/ | Low |
| sketch_image pipeline | whiteboard_demo | frontend/whiteboard/image/ | High |
| Dictation detection | whiteboard_demo | frontend/whiteboard/timing/ | Medium |
| Multi-pass rendering | whiteboard_demo | frontend/whiteboard/painters/ | Medium |
| Centerline config | whiteboard_demo | frontend/whiteboard/text/ | Low |

### Important (Should Port)

| Feature | Source | Target | Effort |
|---------|--------|--------|--------|
| Animation end tracking | whiteboard_demo | frontend/whiteboard/controllers/ | Low |
| Raster underlay | whiteboard_demo | frontend/whiteboard/painters/ | Medium |
| CORS proxy | whiteboard_demo | frontend/whiteboard/services/ | Low |
| Diagram pipeline | whiteboard_demo | frontend/whiteboard/image/ | Medium |

### Nice-to-Have (Optional)

| Feature | Source | Target | Effort |
|---------|--------|--------|--------|
| Curvature timing | visual_whiteboard | frontend/whiteboard/timing/ | Low |
| Travel time | visual_whiteboard | frontend/whiteboard/timing/ | Low |
| Step mode | visual_whiteboard | frontend/whiteboard/debug/ | Low |
| Timing bounds | visual_whiteboard | frontend/whiteboard/timing/ | Low |
| Debug sliders | whiteboard_demo | frontend/whiteboard/debug/ | Medium |

---

*Last updated: 2026-01-29*  
*Related: WHITEBOARD_COMPARISON.md, FEATURE_PARITY_CHECKLIST.md*
