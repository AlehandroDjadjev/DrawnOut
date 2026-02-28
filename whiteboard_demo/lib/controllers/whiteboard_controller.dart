import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/drawable_stroke.dart';
import '../models/stroke_types.dart';
import '../models/timeline.dart';
import '../services/stroke_builder_service.dart';
import '../services/stroke_timing_service.dart';
import '../services/whiteboard_backend_service.dart';
import '../services/backend_vectorizer.dart';
import '../whiteboard/text/chalk_text_preset.dart';
import '../whiteboard/text/text_normalizer.dart';
import '../whiteboard/services/backend_stroke_service.dart' hide CubicSegment;

/// Text item rendered as a Rive overlay on top of the whiteboard canvas.
class WhiteboardRiveTextLayer {
  final String id;
  final String objectName;
  final String text;
  final Offset origin;
  final double fontSize;
  final int replayToken;

  const WhiteboardRiveTextLayer({
    required this.id,
    required this.objectName,
    required this.text,
    required this.origin,
    required this.fontSize,
    required this.replayToken,
  });

  WhiteboardRiveTextLayer copyWith({
    int? replayToken,
  }) {
    return WhiteboardRiveTextLayer(
      id: id,
      objectName: objectName,
      text: text,
      origin: origin,
      fontSize: fontSize,
      replayToken: replayToken ?? this.replayToken,
    );
  }
}

/// Main controller for whiteboard state and operations
class WhiteboardController extends ChangeNotifier {
  // Configuration
  static const double targetResolution = 2000.0;
  static const double basePenWidthPx = 2.4;
  static const double boardWidth = 2000.0;
  static const double boardHeight = 2000.0;

  // Services
  final StrokeBuilderService _strokeBuilder;
  final StrokeTimingService _timingService;
  final WhiteboardBackendService _backendService;

  // State
  List<DrawableStroke> _staticStrokes = [];
  List<DrawableStroke> _animStrokes = [];
  List<WhiteboardRiveTextLayer> _riveTextLayers = [];
  final List<String> _drawnObjectNames = [];
  String? _selectedEraseName;
  String _status = 'Ready';

  // Animation state
  AnimationController? _animController;
  double _animValue = 0.0;
  bool _isAnimating = false;
  bool _animIsText = false;

  // Text rendering settings
  final double _letterGap = 20.0;
  final String _chalkPresetId = ChalkTextPreset.classicId;

  /// Use cubic BÃ©zier glyph strokes (DrawnOutWhiteboard-style). Set false for Rive overlay.
  bool _useRiveText = false;
  int _textReplayToken = 0;

  // Getters
  List<DrawableStroke> get staticStrokes => _staticStrokes;
  List<DrawableStroke> get animStrokes => _animStrokes;
  List<WhiteboardRiveTextLayer> get riveTextLayers =>
      List.unmodifiable(_riveTextLayers);
  List<DrawableStroke> get allStrokes => [..._staticStrokes, ..._animStrokes];
  List<String> get drawnObjectNames => List.unmodifiable(_drawnObjectNames);
  String? get selectedEraseName => _selectedEraseName;
  String get status => _status;
  double get animValue => _animValue;
  bool get isAnimating => _isAnimating;
  bool get useRiveText => _useRiveText;
  StrokeTimingConfig get timingConfig => _timingService.config;

  WhiteboardController({
    StrokeBuilderService? strokeBuilder,
    StrokeTimingService? timingService,
    WhiteboardBackendService? backendService,
    String baseUrl = const String.fromEnvironment(
      'BACKEND_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  })  : _strokeBuilder = strokeBuilder ?? StrokeBuilderService(),
        _timingService = timingService ?? StrokeTimingService(),
        _backendService =
            backendService ?? WhiteboardBackendService(baseUrl: baseUrl);

  /// Toggle between Rive text overlays and vectorized text strokes.
  void setUseRiveText(bool enabled) {
    if (_useRiveText == enabled) return;
    _useRiveText = enabled;
    notifyListeners();
  }

  /// Initialize with animation controller
  void initAnimation(TickerProvider vsync) {
    _animController?.dispose();
    _animController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 20000),
    )
      ..addListener(_onAnimationTick)
      ..addStatusListener(_onAnimationStatus);
  }

  void _onAnimationTick() {
    final v = _animController!.value;
    if ((v - _animValue).abs() > 0.003) {
      _animValue = v;
      notifyListeners();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _animStrokes.isNotEmpty) {
      _staticStrokes = [..._staticStrokes, ..._animStrokes];
      _animStrokes = [];
      _animValue = 1.0;
      _isAnimating = false;
      _status = 'Animation complete. Total strokes: ${_staticStrokes.length}';
      notifyListeners();
    }
  }

  /// Load objects from backend
  Future<void> loadFromBackend() async {
    try {
      _status = 'Loading from backend...';
      notifyListeners();

      final objects = await _backendService.loadObjects();

      for (final obj in objects) {
        if (obj.kind == WhiteboardObjectKind.image) {
          await _addImageInternal(
            fileName: obj.name,
            origin: obj.position,
            scale: obj.scale,
          );
        } else if (obj.kind == WhiteboardObjectKind.text) {
          await _addTextInternal(
            text: obj.name,
            origin: obj.position,
            letterSize: obj.letterSize ?? 180.0,
            letterGap: obj.letterGap ?? _letterGap,
          );
        }
      }

      // Commit all to static
      _commitAnimToStatic();
      _status = 'Loaded ${objects.length} object(s) from backend';
      notifyListeners();
    } catch (e) {
      _status = 'Backend load failed: $e';
      notifyListeners();
    }
  }

  /// Add an image from JSON file
  Future<void> addImage({
    required String fileName,
    required Offset origin,
    double scale = 1.0,
  }) async {
    await _addImageInternal(fileName: fileName, origin: origin, scale: scale);
    _startAnimation();

    // Sync to backend
    try {
      await _backendService.createImage(
        fileName: fileName,
        origin: origin,
        scale: scale,
      );
    } catch (e) {
      _status += ' [Backend sync failed: $e]';
      notifyListeners();
    }
  }

  Future<void> _addImageInternal({
    required String fileName,
    required Offset origin,
    required double scale,
  }) async {
    _status = 'Loading $fileName...';
    notifyListeners();

    try {
      // Fetch JSON from backend
      final url =
          '${_backendService.baseUrl}/api/wb/generate/vectors/$fileName';
      final resp = await http.get(Uri.parse(url));

      if (resp.statusCode != 200) {
        _status = 'Failed to load $fileName: HTTP ${resp.statusCode}';
        notifyListeners();
        return;
      }

      final decoded = json.decode(resp.body);
      if (decoded is! Map || decoded['strokes'] is! List) {
        _status = 'Invalid JSON format';
        notifyListeners();
        return;
      }

      final format =
          (decoded['vector_format'] as String?)?.toLowerCase() ?? 'polyline';
      final List strokesJson = decoded['strokes'] as List;
      final srcWidth = (decoded['width'] as num?)?.toDouble() ?? 1000.0;
      final srcHeight = (decoded['height'] as num?)?.toDouble() ?? 1000.0;

      final polys = <StrokePolyline>[];
      final cubics = <StrokeCubic>[];

      if (format == 'bezier_cubic') {
        for (final s in strokesJson) {
          if (s is! Map || s['segments'] is! List) continue;
          final segs = <CubicSegment>[];
          for (final seg in s['segments']) {
            if (seg is List && seg.length >= 8) {
              segs.add(CubicSegment(
                p0: Offset(
                    (seg[0] as num).toDouble(), (seg[1] as num).toDouble()),
                c1: Offset(
                    (seg[2] as num).toDouble(), (seg[3] as num).toDouble()),
                c2: Offset(
                    (seg[4] as num).toDouble(), (seg[5] as num).toDouble()),
                p1: Offset(
                    (seg[6] as num).toDouble(), (seg[7] as num).toDouble()),
              ));
            }
          }
          if (segs.isNotEmpty) cubics.add(StrokeCubic(segs));
        }
      } else {
        for (final s in strokesJson) {
          if (s is! Map || s['points'] is! List) continue;
          final points = <Offset>[];
          for (final p in s['points']) {
            if (p is List && p.length >= 2) {
              points.add(
                  Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
            }
          }
          if (points.length >= 2) polys.add(StrokePolyline(points));
        }
      }

      // Commit any current animation
      _commitAnimToStatic();

      // Build new strokes
      final newStrokes = _strokeBuilder.buildStrokesForObject(
        jsonName: fileName,
        origin: origin,
        objectScale: scale,
        polylines: polys,
        cubics: cubics,
        srcWidth: srcWidth,
        srcHeight: srcHeight,
      );

      _animStrokes = newStrokes;
      _animIsText = false;

      if (!_drawnObjectNames.contains(fileName)) {
        _drawnObjectNames.add(fileName);
      }
      _selectedEraseName ??= fileName;

      _status = 'Added $fileName (${newStrokes.length} strokes)';
      notifyListeners();
    } catch (e) {
      _status = 'Error loading $fileName: $e';
      notifyListeners();
    }
  }

  /// Add text to the whiteboard
  Future<void> addText({
    required String text,
    required Offset origin,
    double letterSize = 180.0,
    double? letterGap,
  }) async {
    final gap = letterGap ?? _letterGap;
    await _addTextInternal(
      text: text,
      origin: origin,
      letterSize: letterSize,
      letterGap: gap,
    );
    _startAnimation();

    // Sync to backend
    try {
      await _backendService.createText(
        prompt: text,
        origin: origin,
        letterSize: letterSize,
        letterGap: gap,
      );
    } catch (e) {
      _status += ' [Backend sync failed: $e]';
      notifyListeners();
    }
  }

  Future<void> _addTextInternal({
    required String text,
    required Offset origin,
    required double letterSize,
    required double letterGap,
  }) async {
    if (text.isEmpty) {
      _status = 'Text is empty';
      notifyListeners();
      return;
    }

    _status = 'Writing "$text"...';
    notifyListeners();

    // Commit any current animation
    _commitAnimToStatic();

    try {
      if (_useRiveText) {
        _addRiveTextLayer(
          text: text,
          origin: origin,
          letterSize: letterSize,
        );
        return;
      }

      // DrawnOutWhiteboard path: glyph API â†’ cubic BÃ©zier â†’ buildStrokesForText
      final newStrokes = await _buildTextStrokes(
        text,
        origin,
        letterSize,
        letterGap,
      );

      if (newStrokes.isEmpty) {
        _status = 'No strokes generated for "$text"';
        notifyListeners();
        return;
      }

      _animStrokes = newStrokes;
      _animIsText = true;

      if (!_drawnObjectNames.contains(text)) {
        _drawnObjectNames.add(text);
      }
      _selectedEraseName ??= text;

      _status = 'Writing "$text" (${newStrokes.length} strokes)';
      notifyListeners();
    } catch (e) {
      _status = 'Error rendering text: $e';
      debugPrint('Text rendering error: $e');
      notifyListeners();
    }
  }

  void _addRiveTextLayer({
    required String text,
    required Offset origin,
    required double letterSize,
  }) {
    _animController?.stop();
    _animStrokes = [];
    _animValue = 0.0;
    _isAnimating = false;
    _animIsText = true;

    final uniqueId = 'rive_text_${DateTime.now().microsecondsSinceEpoch}';
    final newLayer = WhiteboardRiveTextLayer(
      id: uniqueId,
      objectName: text,
      text: text,
      origin: origin,
      fontSize: letterSize,
      replayToken: _textReplayToken,
    );
    _riveTextLayers = [..._riveTextLayers, newLayer];

    if (!_drawnObjectNames.contains(text)) {
      _drawnObjectNames.add(text);
    }
    _selectedEraseName ??= text;

    _status = 'Writing "$text" (Rive)';
    notifyListeners();
  }

  /// Render text as per-character strokes using the backend vectorizer.
  Future<List<List<Offset>>> _renderTextToStrokes(
    String text,
    double fontSize,
    Offset worldOffset,
  ) async {
    final base = _backendService.baseUrl.trim();
    if (base.isEmpty) {
      debugPrint('Backend vectorizer URL is empty; cannot render text');
      return const [];
    }

    final out = <List<Offset>>[];
    final scaleUp = fontSize < 24 ? (24.0 / fontSize) : 1.0;
    final drawFontSize = fontSize * scaleUp;
    final glyphs = TextNormalizer.expandScriptGlyphs(text);
    var cursorX = 0.0;
    Offset? previousEnd;

    for (final glyph in glyphs) {
      final glyphFontSize = drawFontSize * glyph.sizeFactor;
      final glyphStyle = _textStyleFor(glyphFontSize);
      final advance = _measureTextWidth(glyph.value, glyphStyle) / scaleUp;
      if (glyph.value.trim().isEmpty) {
        cursorX += advance;
        continue;
      }

      final pngBytes = await _renderTextToPng(glyph.value, glyphFontSize);
      final imageSize =
          _imageSizeForText(glyph.value, glyphStyle, glyphFontSize);

      final glyphStrokes = await BackendVectorizer.vectorize(
        baseUrl: base,
        bytes: pngBytes,
        worldScale: 1.0,
        sourceWidth: imageSize.width,
        sourceHeight: imageSize.height,
      );

      final glyphOffset = worldOffset +
          Offset(
            cursorX,
            glyph.baselineShiftEm * fontSize,
          ) +
          Offset(imageSize.width / 2.0, imageSize.height / 2.0);

      final placed = glyphStrokes
          .map((s) => s.map((p) => (p + glyphOffset) / scaleUp).toList())
          .toList();
      final oriented = _orientStrokesForNaturalFlow(
        placed,
        startNear: previousEnd,
      );
      if (oriented.isNotEmpty) {
        previousEnd = oriented.last.last;
      }
      out.addAll(oriented);
      cursorX += advance;
    }

    return out;
  }

  /// Render text to PNG bytes using Flutter's TextPainter
  Future<Uint8List> _renderTextToPng(String text, double fontSize) async {
    final style = _textStyleFor(fontSize);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = math.max(10.0, fontSize * 0.22);
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );
    tp.paint(canvas, Offset(pad, pad));

    // Keep glyph input clean for vectorization; texture is added by stroke pass.

    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  TextStyle _textStyleFor(double fontSize) {
    final preset = ChalkTextPreset.byId(_chalkPresetId);
    return preset.toTextStyle(fontSize: fontSize).copyWith(color: Colors.black);
  }

  double _measureTextWidth(String text, TextStyle style) {
    if (text.isEmpty) return 0.0;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  Size _imageSizeForText(String text, TextStyle style, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = math.max(10.0, fontSize * 0.22);
    final w = (tp.width + pad * 2).ceilToDouble();
    final h = (tp.height + pad * 2).ceilToDouble();
    return Size(w, h);
  }

  List<List<Offset>> _orientStrokesForNaturalFlow(
    List<List<Offset>> strokes, {
    Offset? startNear,
  }) {
    final ordered = <List<Offset>>[];
    Offset? anchor = startNear;
    for (final stroke in strokes.where((s) => s.length >= 2)) {
      if (anchor == null) {
        ordered.add(stroke);
        anchor = stroke.last;
        continue;
      }
      final dStart = (stroke.first - anchor).distance;
      final dEnd = (stroke.last - anchor).distance;
      if (dEnd < dStart) {
        final reversed = stroke.reversed.toList(growable: false);
        ordered.add(reversed);
        anchor = reversed.last;
      } else {
        ordered.add(stroke);
        anchor = stroke.last;
      }
    }
    return ordered;
  }

  /// Convert polylines to drawable strokes using the stroke builder service
  List<DrawableStroke> _buildDrawableStrokesFromPolylines(
    List<List<Offset>> polylines,
    String name,
    Offset origin,
  ) {
    // Convert polylines to StrokePolyline format
    final polys = polylines
        .where((p) => p.length >= 2)
        .map((p) => StrokePolyline(p))
        .toList();

    if (polys.isEmpty) return [];

    // Compute bounds for proper scaling
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final poly in polylines) {
      for (final p in poly) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }
    final srcWidth = maxX - minX;
    final srcHeight = maxY - minY;

    // Use stroke builder to create drawable strokes
    return _strokeBuilder.buildStrokesForObject(
      jsonName: name,
      origin: origin,
      objectScale: 1.0,
      polylines: polys,
      cubics: [],
      srcWidth: srcWidth > 0 ? srcWidth : 100.0,
      srcHeight: srcHeight > 0 ? srcHeight : 100.0,
    );
  }

  // Layout tracking for auto-positioning
  double _nextY = 100.0;
  static const double _headingSize = 120.0;
  static const double _bulletSize = 80.0;
  static const double _lineSpacing = 1.4;
  static const double _leftMargin = 100.0;
  static const double _bulletIndent = 60.0;

  /// Handle drawing actions from timeline
  ///
  /// Accumulates strokes from ALL actions into one continuous animation
  /// (matching segment audio duration) instead of replacing per-action.
  Future<void> handleDrawingActions(List<DrawingAction> actions) async {
    debugPrint('handleDrawingActions called with ${actions.length} actions');

    if (actions.isEmpty) {
      debugPrint('No drawing actions to handle');
      return;
    }

    // Log action type distribution
    final actionTypes = <String, int>{};
    for (final a in actions) {
      actionTypes[a.type] = (actionTypes[a.type] ?? 0) + 1;
    }
    for (final entry in actionTypes.entries) {
      debugPrint('   - ${entry.key}: ${entry.value}');
    }

    _commitAnimToStatic();
    final allStrokes = <DrawableStroke>[];
    var isText = false;

    for (int i = 0; i < actions.length; i++) {
      final action = actions[i];
      final textPreview = action.text.length > 30
          ? '${action.text.substring(0, 30)}...'
          : action.text;
      debugPrint('  [$i] Action type: ${action.type}, text: "$textPreview"');

      try {
        switch (action.type) {
          case 'heading':
            final placement = action.placementValues;
            final hasPlacement = action.placement != null &&
                (placement.x != 0.0 || placement.y != 0.0);
            final x = hasPlacement ? placement.x : _leftMargin;
            final y = hasPlacement ? placement.y : _nextY;
            final fontSize =
                (action.style?['fontSize'] as num?)?.toDouble() ?? _headingSize;
            final headingText = TextNormalizer.normalizeForAction(
              type: action.type,
              text: action.text,
            );
            final strokes = await _buildTextStrokes(
              headingText,
              Offset(x, y),
              fontSize,
              _letterGap,
            );
            allStrokes.addAll(strokes);
            isText = true;
            if (!hasPlacement) _nextY = y + fontSize * _lineSpacing + 40;
            break;

          case 'bullet':
          case 'subbullet':
            final placement = action.placementValues;
            final hasPlacement = action.placement != null &&
                (placement.x != 0.0 || placement.y != 0.0);
            final level = action.level ?? (action.type == 'subbullet' ? 1 : 0);
            final indent = _leftMargin + (level * _bulletIndent);
            final x = hasPlacement ? placement.x : indent;
            final y = hasPlacement ? placement.y : _nextY;
            final fontSize =
                (action.style?['fontSize'] as num?)?.toDouble() ?? _bulletSize;
            final bulletText = TextNormalizer.normalizeForAction(
              type: action.type,
              text: action.text,
            );
            final strokes = await _buildTextStrokes(
              bulletText,
              Offset(x, y),
              fontSize,
              _letterGap,
            );
            allStrokes.addAll(strokes);
            isText = true;
            if (!hasPlacement) _nextY = y + fontSize * _lineSpacing;
            break;

          case 'label':
          case 'formula':
            final placement = action.placementValues;
            final hasPlacement = action.placement != null &&
                (placement.x != 0.0 || placement.y != 0.0);
            final x = hasPlacement ? placement.x : _leftMargin;
            final y = hasPlacement ? placement.y : _nextY;
            final fontSize =
                (action.style?['fontSize'] as num?)?.toDouble() ?? _bulletSize;
            final formulaText = TextNormalizer.normalizeForAction(
              type: action.type,
              text: action.text,
            );
            final strokes = await _buildTextStrokes(
              formulaText,
              Offset(x, y),
              fontSize,
              _letterGap,
            );
            allStrokes.addAll(strokes);
            isText = true;
            if (!hasPlacement) _nextY = y + fontSize * _lineSpacing;
            break;

          case 'sketch_image':
            debugPrint('    -> sketch_image action');
            final strokesJson = action.metadata?['strokes'];
            if (strokesJson is Map<String, dynamic>) {
              final parsed = BackendStrokeService.parseJson(strokesJson);
              if (parsed != null) {
                final placement = action.placementValues;
                final x = placement.x != 0.0 ? placement.x : _leftMargin;
                final y = placement.y != 0.0 ? placement.y : _nextY;
                final drawables = BackendStrokeService.buildDrawableStrokes(
                  strokes: parsed.strokes,
                  srcWidth: parsed.srcWidth,
                  srcHeight: parsed.srcHeight,
                  origin: Offset(x, y),
                  label: 'sketch_image',
                );
                allStrokes.addAll(drawables);
                _nextY = y + parsed.srcHeight * 0.5 + 40;
              }
            }
            break;

          default:
            debugPrint('    Unknown action type: ${action.type}');
        }
      } catch (e, st) {
        debugPrint('    Error handling action: $e');
        debugPrint('    Stack: $st');
      }
    }

    if (allStrokes.isNotEmpty) {
      _animStrokes = allStrokes;
      _animIsText = isText;
      for (final a in actions) {
        final name = a.text.isNotEmpty
            ? a.text
            : (a.isSketchImage ? 'sketch_image' : '');
        if (name.isNotEmpty && !_drawnObjectNames.contains(name)) {
          _drawnObjectNames.add(name);
        }
      }
      _selectedEraseName ??=
          _drawnObjectNames.isNotEmpty ? _drawnObjectNames.last : null;
      _status = 'Drawing ${allStrokes.length} strokes';
      notifyListeners();
      _startAnimation();
    }
    debugPrint('handleDrawingActions completed: ${allStrokes.length} strokes');
  }

  /// Build drawable strokes for text (glyph path or vectorizer fallback).
  /// Does not animate; used by handleDrawingActions for accumulation.
  Future<List<DrawableStroke>> _buildTextStrokes(
    String text,
    Offset origin,
    double letterSize,
    double letterGap,
  ) async {
    if (text.isEmpty) return [];
    if (_useRiveText) return []; // Rive path doesn't produce strokes

    // Try backend create_text_object first (same as visual_whiteboard; works on web)
    final strokeData = await _backendService.fetchTextStrokes(
      prompt: text,
      origin: origin,
      letterSize: letterSize,
      letterGap: letterGap,
    );
    if (strokeData != null) {
      final parsed = BackendStrokeService.parseJson(strokeData);
      if (parsed != null && parsed.strokes.isNotEmpty) {
        return BackendStrokeService.buildDrawableStrokesFromWorldSpace(
          strokes: parsed.strokes,
          origin: origin,
          label: text,
        );
      }
    }

    // Fallback: render to PNG and vectorize (requires /api/wb/vectorize/ or local)
    final strokes = await _renderTextToStrokes(text, letterSize, origin);
    return _buildDrawableStrokesFromPolylines(strokes, text, origin);
  }

  /// Reset layout state (call when starting a new lesson)
  void resetLayout() {
    _nextY = 100.0;
    notifyListeners();
  }

  /// Handle drawing actions with explicit duration (from dictation detection)
  ///
  /// This method is called by TimelinePlaybackController with the calculated
  /// draw duration based on dictation detection.
  Future<void> handleDrawingActionsWithDuration(
    List<DrawingAction> actions,
    double drawDurationSeconds,
  ) async {
    debugPrint(
        'handleDrawingActionsWithDuration: ${actions.length} actions, ${drawDurationSeconds.toStringAsFixed(1)}s');

    // TODO: Use drawDurationSeconds to set animation controller duration
    // For now, delegate to standard handler
    await handleDrawingActions(actions);
  }

  /// Erase object by name
  Future<void> eraseObject(String name) async {
    if (name.isEmpty) return;

    _staticStrokes = _staticStrokes.where((s) => s.jsonName != name).toList();
    _animStrokes = _animStrokes.where((s) => s.jsonName != name).toList();
    _riveTextLayers =
        _riveTextLayers.where((layer) => layer.objectName != name).toList();
    _drawnObjectNames.remove(name);

    if (_drawnObjectNames.isEmpty) {
      _selectedEraseName = null;
    } else if (_selectedEraseName == name) {
      _selectedEraseName = _drawnObjectNames.last;
    }

    if (_animStrokes.isEmpty) {
      _animController?.stop();
      _animValue = 0.0;
      _isAnimating = false;
    }

    final remaining = allStrokes.length + _riveTextLayers.length;
    _status = 'Erased "$name". Remaining: $remaining objects';
    notifyListeners();

    // Sync to backend
    try {
      await _backendService.deleteObject(name);
    } catch (e) {
      _status += ' [Backend delete failed: $e]';
      notifyListeners();
    }
  }

  /// Set selected object for erase
  void setSelectedEraseName(String? name) {
    _selectedEraseName = name;
    notifyListeners();
  }

  /// Clear the entire board
  void clear() {
    _animController?.stop();
    _staticStrokes = [];
    _animStrokes = [];
    _riveTextLayers = [];
    _drawnObjectNames.clear();
    _selectedEraseName = null;
    _animValue = 0.0;
    _isAnimating = false;
    _textReplayToken = 0;
    _status = 'Board cleared';
    notifyListeners();
  }

  /// Replay the current animation
  void replayAnimation() {
    if (_animStrokes.isEmpty) {
      if (_riveTextLayers.isNotEmpty) {
        _textReplayToken++;
        _riveTextLayers = _riveTextLayers
            .map((layer) => layer.copyWith(replayToken: _textReplayToken))
            .toList();
        _status = 'Replaying text animation';
        notifyListeners();
        return;
      }
      _status = 'No animation to replay';
      notifyListeners();
      return;
    }
    _animController?.reset();
    _animController?.forward();
    _isAnimating = true;
    notifyListeners();
  }

  /// Update timing configuration
  void updateTimingConfig(StrokeTimingConfig config) {
    _timingService.config = config;
    if (_animStrokes.isNotEmpty) {
      _recomputeTiming();
    }
  }

  void _commitAnimToStatic() {
    if (_animStrokes.isNotEmpty) {
      _animController?.stop();
      _staticStrokes = [..._staticStrokes, ..._animStrokes];
      _animStrokes = [];
      _animValue = 0.0;
      _isAnimating = false;
    }
  }

  void _startAnimation() {
    if (_animStrokes.isEmpty || _animController == null) return;

    final totalSeconds = _timingService.computeTiming(
      _animStrokes,
      isText: _animIsText,
    );

    if (totalSeconds <= 0.0) {
      _commitAnimToStatic();
      return;
    }

    final ms = (totalSeconds * 1000).round().clamp(1, 600000);
    _animController!.duration = Duration(milliseconds: ms);
    _animController!.reset();
    _animController!.forward();
    _animValue = 0.0;
    _isAnimating = true;
    notifyListeners();
  }

  void _recomputeTiming() {
    if (_animStrokes.isEmpty) return;
    _timingService.computeTiming(_animStrokes, isText: _animIsText);
    _startAnimation();
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }
}
