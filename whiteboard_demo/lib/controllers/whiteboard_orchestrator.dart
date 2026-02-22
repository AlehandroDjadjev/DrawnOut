// controllers/whiteboard_orchestrator.dart
//
// Orchestrates whiteboard drawing operations, layout management,
// and content rendering. Extracted from main.dart for clean separation.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../vectorizer.dart';
import '../services/backend_vectorizer.dart';
import '../assistant_api.dart';
import '../services/timeline_api.dart';
import '../services/lesson_pipeline_api.dart';
import '../whiteboard/whiteboard.dart';
import 'timeline_playback_controller.dart';

// Re-export from whiteboard module for convenience
export '../whiteboard/layout/layout_config.dart' show Fonts, Indent;
export '../whiteboard/layout/layout_state.dart' show RenderedLine, BBox, DrawnBlock;

/// Vectorization configuration.
class VectorizerConfig {
  String edgeMode;
  double blurK;
  double cannyLo;
  double cannyHi;
  double dogSigma;
  double dogK;
  double dogThresh;
  double epsilon;
  double resample;
  double minPerim;
  bool externalOnly;
  double worldScale;
  double angleThreshold;
  double angleWindow;
  double smoothPasses;
  bool mergeParallel;
  double mergeMaxDist;
  double minStrokeLen;
  double minStrokePoints;

  VectorizerConfig({
    this.edgeMode = 'Canny',
    this.blurK = 5,
    this.cannyLo = 50,
    this.cannyHi = 160,
    this.dogSigma = 1.2,
    this.dogK = 1.6,
    this.dogThresh = 6.0,
    this.epsilon = 1.1187500000000001,
    this.resample = 1.410714285714286,
    this.minPerim = 19.839285714285793,
    this.externalOnly = false,
    this.worldScale = 1.0,
    this.angleThreshold = 30.0,
    this.angleWindow = 4,
    this.smoothPasses = 3,
    this.mergeParallel = true,
    this.mergeMaxDist = 12.0,
    this.minStrokeLen = 8.70,
    this.minStrokePoints = 6,
  });
}

/// Centerline rendering configuration.
class CenterlineParams {
  double threshold;
  double epsilon;
  double resample;
  double mergeFactor;
  double mergeMin;
  double mergeMax;
  double smoothPasses;
  bool preferOutlineHeadings;
  bool sketchPreferOutline;

  CenterlineParams({
    this.threshold = 60.0,
    this.epsilon = 0.6,
    this.resample = 0.8,
    this.mergeFactor = 0.9,
    this.mergeMin = 12.0,
    this.mergeMax = 36.0,
    this.smoothPasses = 3.0,
    this.preferOutlineHeadings = true,
    this.sketchPreferOutline = false,
  });
}

/// Playback/style configuration.
class PlaybackConfig {
  double seconds;
  int passes;
  double opacity;
  double width;
  double jitterAmp;
  double jitterFreq;
  bool showRasterUnder;
  bool planUnderlay;
  bool debugAllowUnderDiagrams;

  PlaybackConfig({
    this.seconds = 60,
    this.passes = 1,
    this.opacity = 0.8,
    this.width = 5,
    this.jitterAmp = 0,
    this.jitterFreq = 0.02,
    this.showRasterUnder = true,
    this.planUnderlay = true,
    this.debugAllowUnderDiagrams = false,
  });
}

/// Layout configuration values.
class LayoutParams {
  double marginTop;
  double marginRight;
  double marginBottom;
  double marginLeft;
  double lineHeight;
  double gutterY;
  double indent1;
  double indent2;
  double indent3;
  double heading;
  double body;
  double tiny;
  int columnsCount;
  double columnsGutter;

  LayoutParams({
    this.marginTop = 60,
    this.marginRight = 64,
    this.marginBottom = 60,
    this.marginLeft = 64,
    this.lineHeight = 1.25,
    this.gutterY = 14,
    this.indent1 = 32,
    this.indent2 = 64,
    this.indent3 = 96,
    this.heading = 60,
    this.body = 60,
    this.tiny = 60,
    this.columnsCount = 1,
    this.columnsGutter = 48,
  });
}

/// Tutor draw configuration.
class TutorConfig {
  bool useSpeed;
  double seconds;
  double fontScale;
  bool useFixedFont;
  double fixedFont;
  double minFont;

  TutorConfig({
    this.useSpeed = true,
    this.seconds = 60,
    this.fontScale = 1.0,
    this.useFixedFont = true,
    this.fixedFont = 72.0,
    this.minFont = 72.0,
  });
}

/// Main orchestrator for whiteboard operations.
///
/// Manages drawing state, layout, vectorization, and content rendering.
/// Extends ChangeNotifier to allow UI to react to state changes.
class WhiteboardOrchestrator extends ChangeNotifier {
  // Constants
  static const double defaultCanvasW = 1600;
  static const double defaultCanvasH = 1000;

  // Services
  final StrokeService _strokeService = const StrokeService();
  final TextSketchService _textSketchService = const TextSketchService();
  late ImageSketchService _imageSketchService;

  // Core state
  final List<VectorObject> board = [];
  Uint8List? uploadedBytes;
  ui.Image? uploadedImage;
  PlacedImage? raster;
  StrokePlan? plan;
  DateTime? currentAnimEnd;
  bool diagramInFlight = false;
  DateTime? diagramAnimEnd;
  bool busy = false;
  String? lastError;

  // Canvas size
  Size? canvasSize;

  // Layout
  LayoutState? layout;

  // Configuration objects
  final VectorizerConfig vectorConfig = VectorizerConfig();
  final CenterlineParams centerlineParams = CenterlineParams();
  final PlaybackConfig playbackConfig = PlaybackConfig();
  final LayoutParams layoutParams = LayoutParams();
  final TutorConfig tutorConfig = TutorConfig();

  // API clients
  String baseUrl;
  AssistantApiClient? api;
  int? sessionId;
  TimelineApiClient? timelineApi;
  TimelinePlaybackController? timelineController;

  // Timers
  Timer? autoNextTimer;

  WhiteboardOrchestrator({this.baseUrl = 'http://localhost:8000'}) {
    _imageSketchService = ImageSketchService(baseUrl: baseUrl);
  }

  /// Update the base URL for API calls.
  void setBaseUrl(String url) {
    baseUrl = url.trim().isEmpty ? 'http://localhost:8000' : url.trim();
    _imageSketchService = ImageSketchService(baseUrl: baseUrl);
    api = AssistantApiClient(baseUrl);
    timelineApi = TimelineApiClient(baseUrl);
    timelineController?.setBaseUrl(baseUrl);
    notifyListeners();
  }

  /// Set the canvas size for layout calculations.
  void setCanvasSize(Size size) {
    final prev = canvasSize;
    if (prev != null &&
        (prev.width - size.width).abs() < 1 &&
        (prev.height - size.height).abs() < 1) return;
    canvasSize = size;
    // Rebuild layout config for new page size
    if (layout != null) {
      final newCfg = buildLayoutConfigForSize(size.width, size.height);
      layout = LayoutState(
        config: newCfg,
        cursorY: layout!.cursorY.clamp(newCfg.page.top, newCfg.page.height - newCfg.page.bottom),
        columnIndex: 0,
        blocks: layout!.blocks,
        sectionCount: layout!.sectionCount,
      );
      notifyListeners();
    }
  }

  /// Set busy state and notify listeners.
  void setBusy(bool value) {
    if (busy != value) {
      busy = value;
      notifyListeners();
    }
  }

  /// Set error message.
  void setError(String? msg) {
    lastError = msg;
    notifyListeners();
  }

  // ============================================================
  // Layout Management
  // ============================================================

  /// Ensure layout is initialized.
  Future<void> ensureLayout() async {
    layout ??= makeLayout();
  }

  /// Create a new layout state.
  LayoutState makeLayout() {
    final cfg = buildLayoutConfigForSize(
      canvasSize?.width ?? defaultCanvasW,
      canvasSize?.height ?? defaultCanvasH,
    );
    return LayoutState(
      config: cfg,
      cursorY: cfg.page.top,
      columnIndex: 0,
      blocks: <DrawnBlock>[],
      sectionCount: 0,
    );
  }

  /// Build layout configuration for given canvas size.
  LayoutConfig buildLayoutConfigForSize(double w, double h) {
    final columns = (layoutParams.columnsCount <= 1)
        ? null
        : Columns(
            count: layoutParams.columnsCount.clamp(1, 4),
            gutter: layoutParams.columnsGutter,
          );
    return LayoutConfig(
      page: PageConfig(
        width: w,
        height: h,
        top: layoutParams.marginTop,
        right: layoutParams.marginRight,
        bottom: layoutParams.marginBottom,
        left: layoutParams.marginLeft,
      ),
      lineHeight: layoutParams.lineHeight,
      gutterY: layoutParams.gutterY,
      indent: Indent(
        level1: layoutParams.indent1,
        level2: layoutParams.indent2,
        level3: layoutParams.indent3,
      ),
      fonts: Fonts(
        heading: layoutParams.heading,
        body: layoutParams.body,
        tiny: layoutParams.tiny,
      ),
      columns: columns,
    );
  }

  /// Reset layout to initial state.
  void resetLayout() {
    layout = makeLayout();
    notifyListeners();
  }

  // ============================================================
  // Board Management
  // ============================================================

  /// Clear the board.
  void clearBoard() {
    board.clear();
    plan = null;
    raster = null;
    uploadedBytes = null;
    uploadedImage = null;
    layout = null;
    notifyListeners();
  }

  /// Undo last board item.
  void undoLast() {
    if (board.isNotEmpty) {
      board.removeLast();
      notifyListeners();
    }
  }

  /// Commit current sketch to board.
  void commitCurrentSketch() {
    if (plan == null) return;
    final obj = VectorObject(
      plan: plan!,
      baseWidth: playbackConfig.width,
      passOpacity: playbackConfig.opacity,
      passes: playbackConfig.passes,
      jitterAmp: playbackConfig.jitterAmp,
      jitterFreq: playbackConfig.jitterFreq,
    );
    board.add(obj);
    plan = null;
    notifyListeners();
  }

  // ============================================================
  // Text Rendering
  // ============================================================

  /// Render text to PNG bytes.
  Future<Uint8List> renderTextImageBytes(String text, double fontSize) async {
    return _textSketchService.renderTextToPng(text, fontSize);
  }

  /// Render a single line to PNG with dimensions.
  Future<RenderedLine> renderTextLine(String text, double fontSize) async {
    final result = await _textSketchService.renderTextLine(text, fontSize);
    return RenderedLine(bytes: result.bytes, w: result.w, h: result.h);
  }

  /// Choose font size based on action type.
  double chooseFont(String type, Fonts fonts, Map<String, dynamic>? style) {
    if (style != null && style['fontSize'] is num) {
      return (style['fontSize'] as num).toDouble();
    }
    if (type == 'heading') return fonts.heading;
    if (type == 'formula') return fonts.heading;
    return fonts.body;
  }

  /// Get indentation for action type and level.
  double indentFor(String type, int level, Indent indent) {
    if (type == 'bullet') {
      if (level <= 1) return indent.level1;
      if (level == 2) return indent.level2;
      return indent.level3;
    }
    if (type == 'subbullet') {
      if (level <= 1) return indent.level2;
      if (level == 2) return indent.level3;
      return indent.level3 + 24;
    }
    return 0.0;
  }

  /// Wrap text to fit width.
  List<String> wrapText(String text, double fontSize, double maxWidth) {
    return _textSketchService.wrapText(text, fontSize, maxWidth);
  }

  /// Find next Y position that doesn't collide with existing blocks.
  double nextNonCollidingY(
    double proposedY,
    double x,
    double w,
    double h,
    List<DrawnBlock> blocks,
  ) {
    var y = proposedY;
    const maxIterations = 100;
    for (var i = 0; i < maxIterations; i++) {
      final candidate = BBox(x: x, y: y, w: w, h: h);
      bool collides = false;
      for (final blk in blocks) {
        if (candidate.intersects(blk.bbox)) {
          y = blk.bbox.bottom + 4;
          collides = true;
          break;
        }
      }
      if (!collides) return y;
    }
    return y;
  }

  // ============================================================
  // Vectorization
  // ============================================================

  /// Vectorize image bytes. Uses backend API when baseUrl is set.
  Future<List<List<Offset>>> vectorize(Uint8List bytes) async {
    if (baseUrl.isNotEmpty) {
      return BackendVectorizer.vectorize(baseUrl: baseUrl, bytes: bytes);
    }
    return Vectorizer.vectorize(
      bytes: bytes,
      worldScale: vectorConfig.worldScale,
      edgeMode: vectorConfig.edgeMode,
      blurK: vectorConfig.blurK.round(),
      cannyLo: vectorConfig.cannyLo,
      cannyHi: vectorConfig.cannyHi,
      dogSigma: vectorConfig.dogSigma,
      dogK: vectorConfig.dogK,
      dogThresh: vectorConfig.dogThresh,
      epsilon: vectorConfig.epsilon,
      resampleSpacing: vectorConfig.resample,
      minPerimeter: vectorConfig.minPerim,
      retrExternalOnly: vectorConfig.externalOnly,
      angleThresholdDeg: vectorConfig.angleThreshold,
      angleWindow: vectorConfig.angleWindow.round(),
      smoothPasses: vectorConfig.smoothPasses.round(),
      mergeParallel: vectorConfig.mergeParallel,
      mergeMaxDist: vectorConfig.mergeMaxDist,
      minStrokeLen: vectorConfig.minStrokeLen,
      minStrokePoints: vectorConfig.minStrokePoints.round(),
    );
  }

  /// Vectorize and create sketch from uploaded image.
  Future<void> vectorizeAndSketch({
    required double x,
    required double y,
    required double targetWidth,
  }) async {
    if (uploadedBytes == null) {
      setError('Upload an image first');
      return;
    }
    setBusy(true);
    try {
      final strokes = await vectorize(uploadedBytes!);
      _onVectorized(strokes, x, y, targetWidth);
    } catch (e) {
      debugPrint('Vectorize error: $e');
      setError(e.toString());
    } finally {
      setBusy(false);
    }
  }

  void _onVectorized(List<List<Offset>> strokes, double x, double y, double targetWidth) {
    if (strokes.isEmpty) {
      setError('No strokes found');
      return;
    }

    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final s in strokes) {
      for (final p in s) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    final rawW = maxX - minX;
    final rawH = maxY - minY;
    final scale = rawW > 0 ? targetWidth / rawW : 1.0;
    final scaledH = rawH * scale;

    // Center the strokes at (x, y)
    final cx = minX + rawW / 2;
    final cy = minY + rawH / 2;
    final transformed = strokes.map((s) {
      return s.map((p) {
        final dx = (p.dx - cx) * scale + x;
        final dy = (p.dy - cy) * scale + y;
        return Offset(dx, dy);
      }).toList();
    }).toList();

    // Update raster position if we have one
    if (uploadedImage != null) {
      raster = PlacedImage(
        image: uploadedImage!,
        worldCenter: Offset(x, y),
        worldSize: Size(targetWidth, scaledH),
      );
    }

    plan = StrokePlan(transformed);
    notifyListeners();
  }

  /// Sketch text with current config.
  Future<void> sketchText(String text, {double? fontSize}) async {
    if (text.trim().isEmpty) {
      setError('Enter some text first');
      return;
    }
    setBusy(true);
    try {
      final usedFont = fontSize ?? tutorConfig.minFont;
      final actualFont = usedFont < tutorConfig.minFont ? tutorConfig.minFont : usedFont;
      final png = await renderTextImageBytes(text, actualFont);

      final centerlineMode = !centerlineParams.sketchPreferOutline && actualFont < centerlineParams.threshold;
      final mergeDist = centerlineMode
          ? (actualFont * centerlineParams.mergeFactor).clamp(centerlineParams.mergeMin, centerlineParams.mergeMax)
          : 10.0;

      final strokes = baseUrl.isNotEmpty
          ? await BackendVectorizer.vectorize(baseUrl: baseUrl, bytes: png)
          : await Vectorizer.vectorize(
              bytes: png,
              worldScale: vectorConfig.worldScale,
              edgeMode: 'Canny',
              blurK: 3,
              cannyLo: 30.0,
              cannyHi: 120.0,
              dogSigma: vectorConfig.dogSigma,
              dogK: vectorConfig.dogK,
              dogThresh: vectorConfig.dogThresh,
              epsilon: centerlineMode ? centerlineParams.epsilon : 0.8,
              resampleSpacing: centerlineMode ? centerlineParams.resample : 1.0,
              minPerimeter: (vectorConfig.minPerim * 0.6).clamp(6.0, 1e9),
              retrExternalOnly: false,
              angleThresholdDeg: 85.0,
              angleWindow: 3,
              smoothPasses: centerlineMode ? centerlineParams.smoothPasses.round() : 1,
              mergeParallel: true,
              mergeMaxDist: mergeDist,
              minStrokeLen: 4.0,
              minStrokePoints: 3,
            );

      // Normalize direction and order by x
      final normalized = strokes.map((s) {
        if (s.isEmpty) return s;
        return s.first.dx <= s.last.dx ? s : s.reversed.toList();
      }).toList();
      normalized.sort((a, b) {
        final ax = a.map((p) => p.dx).reduce(math.min);
        final bx = b.map((p) => p.dx).reduce(math.min);
        return ax.compareTo(bx);
      });

      // Stitch nearby endpoints
      final stitched = _strokeService.stitchStrokes(
        normalized,
        maxGap: (actualFont * 0.08).clamp(3.0, 18.0),
      );

      final offset = raster?.worldCenter ?? Offset.zero;
      final placed = stitched.map((s) => s.map((p) => p + offset).toList()).toList();
      plan = StrokePlan(placed);
      notifyListeners();
    } catch (e, st) {
      debugPrint('SketchText error: $e\n$st');
      setError(e.toString());
    } finally {
      setBusy(false);
    }
  }

  // ============================================================
  // Image Handling
  // ============================================================

  /// Load image from bytes.
  Future<void> loadImageBytes(Uint8List bytes) async {
    uploadedBytes = bytes;
    uploadedImage = await _decodeImage(bytes);
    notifyListeners();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) => c.complete(img));
    return c.future;
  }

  /// Sketch image from URL (for sketch_image actions).
  Future<void> sketchImageFromUrl({
    required String url,
    double? x,
    double? y,
    double? width,
    double? height,
    String? name,
  }) async {
    setBusy(true);
    try {
      // Use CORS proxy if needed
      final proxiedUrl = LessonPipelineApi.proxyImageUrl(url, baseUrl: baseUrl);
      final response = await http.get(Uri.parse(proxiedUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch image: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      await loadImageBytes(bytes);

      // Determine placement
      final targetX = x ?? (canvasSize?.width ?? defaultCanvasW) / 2;
      final targetY = y ?? (canvasSize?.height ?? defaultCanvasH) / 2;
      final targetW = width ?? 400.0;

      await vectorizeAndSketch(x: targetX, y: targetY, targetWidth: targetW);

      // Commit to board
      if (plan != null) {
        final obj = VectorObject(
          plan: plan!,
          baseWidth: playbackConfig.width,
          passOpacity: playbackConfig.opacity,
          passes: playbackConfig.passes,
          jitterAmp: playbackConfig.jitterAmp,
          jitterFreq: playbackConfig.jitterFreq,
        );
        board.add(obj);
        plan = null;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('sketchImageFromUrl error: $e');
      setError(e.toString());
    } finally {
      setBusy(false);
    }
  }

  // ============================================================
  // Diagram Generation
  // ============================================================

  /// Fetch and sketch a diagram from prompt.
  Future<void> fetchAndSketchDiagram(String prompt) async {
    if (prompt.trim().isEmpty) {
      setError('Enter a diagram description');
      return;
    }
    setBusy(true);
    diagramInFlight = true;
    try {
      final uri = Uri.parse('$baseUrl/api/lessons/diagram/');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prompt': prompt}),
      );
      if (response.statusCode != 200) {
        throw Exception('Diagram API error: ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      final svgOrPng = data['image'] as String?;
      if (svgOrPng == null || svgOrPng.isEmpty) {
        throw Exception('No image in response');
      }

      // Decode base64 image
      final bytes = base64Decode(svgOrPng);
      await loadImageBytes(bytes);

      // Vectorize at center
      final targetX = (canvasSize?.width ?? defaultCanvasW) / 2;
      final targetY = (canvasSize?.height ?? defaultCanvasH) / 2;
      await vectorizeAndSketch(x: targetX, y: targetY, targetWidth: 600);
    } catch (e) {
      debugPrint('Diagram fetch error: $e');
      setError(e.toString());
    } finally {
      diagramInFlight = false;
      setBusy(false);
    }
  }

  // ============================================================
  // Block Placement (for orchestrated actions)
  // ============================================================

  /// Place a content block on the whiteboard.
  Future<void> placeBlock({
    required String type,
    required String text,
    int level = 1,
    Map<String, dynamic>? style,
    double? audioSeconds,
    bool preferOutline = false,
  }) async {
    await ensureLayout();
    final cfg = layout!.config;
    final fonts = cfg.fonts;
    final indent = cfg.indent;

    double fontSize = chooseFont(type, fonts, style);
    if (tutorConfig.useFixedFont) {
      fontSize = tutorConfig.fixedFont;
    }
    fontSize = math.max(fontSize, tutorConfig.minFont);

    final indentPx = indentFor(type, level, indent);
    final colWidth = layout!.columnWidth();
    final availableWidth = colWidth - indentPx;

    // Wrap text
    final lines = wrapText(text, fontSize, availableWidth);
    final lineH = fontSize * cfg.lineHeight;

    // Calculate block height
    final blockH = lines.length * lineH;

    // Get X position based on column
    final colX = cfg.page.left + layout!.columnOffsetX();
    final x = colX + indentPx;

    // Find non-colliding Y
    var y = nextNonCollidingY(
      layout!.cursorY,
      x,
      availableWidth,
      blockH,
      layout!.blocks,
    );

    // Render each line
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineY = y + i * lineH;

      // Scale small fonts for better vectorization
      final scaleUp = fontSize < 24 ? (24.0 / fontSize) : 1.0;
      final renderedLine = await renderTextLine(line, fontSize * scaleUp);

      final centerlineMode = !preferOutline && fontSize < centerlineParams.threshold;
      final mergeDist = centerlineMode
          ? (fontSize * centerlineParams.mergeFactor).clamp(centerlineParams.mergeMin, centerlineParams.mergeMax)
          : 10.0;

      final strokes = baseUrl.isNotEmpty
          ? await BackendVectorizer.vectorize(baseUrl: baseUrl, bytes: renderedLine.bytes)
          : await Vectorizer.vectorize(
              bytes: renderedLine.bytes,
              worldScale: vectorConfig.worldScale / scaleUp,
              edgeMode: 'Canny',
              blurK: 3,
              cannyLo: 30.0,
              cannyHi: 120.0,
              epsilon: centerlineMode ? centerlineParams.epsilon : 0.8,
              resampleSpacing: centerlineMode ? centerlineParams.resample : 1.0,
              minPerimeter: 6.0,
              retrExternalOnly: false,
              angleThresholdDeg: 85.0,
              angleWindow: 3,
              smoothPasses: centerlineMode ? centerlineParams.smoothPasses.round() : 1,
              mergeParallel: true,
              mergeMaxDist: mergeDist,
              minStrokeLen: 4.0,
              minStrokePoints: 3,
            );

      // Normalize and stitch
      final normalized = strokes.map((s) {
        if (s.isEmpty) return s;
        return s.first.dx <= s.last.dx ? s : s.reversed.toList();
      }).toList();
      normalized.sort((a, b) {
        final ax = a.isEmpty ? 0.0 : a.map((p) => p.dx).reduce(math.min);
        final bx = b.isEmpty ? 0.0 : b.map((p) => p.dx).reduce(math.min);
        return ax.compareTo(bx);
      });

      final stitched = _strokeService.stitchStrokes(
        normalized,
        maxGap: (fontSize * 0.08).clamp(3.0, 18.0),
      );

      // Offset strokes to position
      final placed = stitched.map((s) {
        return s.map((p) => Offset(p.dx + x, p.dy + lineY)).toList();
      }).toList();

      // Create and commit vector object
      final linePlan = StrokePlan(placed);
      final obj = VectorObject(
        plan: linePlan,
        baseWidth: playbackConfig.width,
        passOpacity: playbackConfig.opacity,
        passes: playbackConfig.passes,
        jitterAmp: playbackConfig.jitterAmp,
        jitterFreq: playbackConfig.jitterFreq,
      );
      board.add(obj);
    }

    // Update layout state
    final blockBox = BBox(x: x, y: y, w: availableWidth, h: blockH);
    final blockId = '${type}_${DateTime.now().millisecondsSinceEpoch}';
    layout!.blocks.add(DrawnBlock(id: blockId, type: type, bbox: blockBox));
    layout!.cursorY = y + blockH + cfg.gutterY;

    notifyListeners();
  }

  // ============================================================
  // Whiteboard Actions Handling
  // ============================================================

  /// Handle a list of whiteboard actions.
  Future<void> handleWhiteboardActions(List<dynamic> actions) async {
    for (final action in actions) {
      if (action is! Map<String, dynamic>) continue;

      final type = action['type'] as String? ?? '';
      final text = action['text'] as String? ?? '';
      final level = action['level'] as int? ?? 1;
      final style = action['style'] as Map<String, dynamic>?;

      if (type == 'sketch_image') {
        // Handle image action
        final imageUrl = action['image_url'] as String? ??
            action['url'] as String? ??
            action['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          await sketchImageFromUrl(
            url: imageUrl,
            x: (action['x'] as num?)?.toDouble(),
            y: (action['y'] as num?)?.toDouble(),
            width: (action['width'] as num?)?.toDouble(),
            height: (action['height'] as num?)?.toDouble(),
            name: action['name'] as String?,
          );
        }
      } else if (text.isNotEmpty) {
        // Handle text-based actions
        final preferOutline = type == 'heading' && centerlineParams.preferOutlineHeadings;
        await placeBlock(
          type: type,
          text: text,
          level: level,
          style: style,
          preferOutline: preferOutline,
        );
      }
    }
  }

  /// Check if segment can advance (animation complete).
  bool canAdvanceSegment() {
    final now = DateTime.now();
    if (currentAnimEnd != null && now.isBefore(currentAnimEnd!)) {
      return false;
    }
    if (diagramInFlight) return false;
    if (diagramAnimEnd != null && now.isBefore(diagramAnimEnd!)) {
      return false;
    }
    return true;
  }

  // ============================================================
  // Cleanup
  // ============================================================

  @override
  void dispose() {
    autoNextTimer?.cancel();
    timelineController?.dispose();
    super.dispose();
  }
}
