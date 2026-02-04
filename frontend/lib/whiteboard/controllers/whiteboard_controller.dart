import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/stroke_types.dart';
import '../models/drawable_stroke.dart';
import '../models/timeline.dart';
import '../services/stroke_builder_service.dart';
import '../services/stroke_timing_service.dart';
import '../services/whiteboard_backend_service.dart';
import '../services/vectorizer.dart';

/// Main controller for whiteboard state and operations
class WhiteboardController extends ChangeNotifier {
  // Configuration
  static const double targetResolution = 2000.0;
  static const double basePenWidthPx = 3.0;
  static const double boardWidth = 2000.0;
  static const double boardHeight = 2000.0;

  // Services
  final StrokeBuilderService _strokeBuilder;
  final StrokeTimingService _timingService;
  final WhiteboardBackendService _backendService;

  // State
  List<DrawableStroke> _staticStrokes = [];
  List<DrawableStroke> _animStrokes = [];
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

  // Getters
  List<DrawableStroke> get staticStrokes => _staticStrokes;
  List<DrawableStroke> get animStrokes => _animStrokes;
  List<DrawableStroke> get allStrokes => [..._staticStrokes, ..._animStrokes];
  List<String> get drawnObjectNames => List.unmodifiable(_drawnObjectNames);
  String? get selectedEraseName => _selectedEraseName;
  String get status => _status;
  double get animValue => _animValue;
  bool get isAnimating => _isAnimating;
  StrokeTimingConfig get timingConfig => _timingService.config;

  WhiteboardController({
    StrokeBuilderService? strokeBuilder,
    StrokeTimingService? timingService,
    WhiteboardBackendService? backendService,
    String baseUrl = 'http://127.0.0.1:8000',
  })  : _strokeBuilder = strokeBuilder ?? StrokeBuilderService(),
        _timingService = timingService ?? StrokeTimingService(),
        _backendService = backendService ?? WhiteboardBackendService(baseUrl: baseUrl);

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
      final url = '${_backendService.baseUrl}/api/wb/generate/vectors/$fileName';
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

      final format = (decoded['vector_format'] as String?)?.toLowerCase() ?? 'polyline';
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
                p0: Offset((seg[0] as num).toDouble(), (seg[1] as num).toDouble()),
                c1: Offset((seg[2] as num).toDouble(), (seg[3] as num).toDouble()),
                c2: Offset((seg[4] as num).toDouble(), (seg[5] as num).toDouble()),
                p1: Offset((seg[6] as num).toDouble(), (seg[7] as num).toDouble()),
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
              points.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
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
      // Use local text-to-vector rendering (like whiteboard_demo)
      final strokes = await _renderTextToStrokes(text, letterSize, origin);
      
      if (strokes.isEmpty) {
        _status = 'No strokes generated for "$text"';
        notifyListeners();
        return;
      }

      // Convert polylines to drawable strokes
      final newStrokes = _buildDrawableStrokesFromPolylines(
        strokes, 
        text, 
        origin,
      );

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

  /// Render text to PNG and vectorize it locally (like whiteboard_demo)
  Future<List<List<Offset>>> _renderTextToStrokes(
    String text, 
    double fontSize,
    Offset worldOffset,
  ) async {
    // Render text to PNG bytes using TextPainter
    final pngBytes = await _renderTextToPng(text, fontSize);
    
    // Use centerline mode for smaller fonts, outline for larger
    final centerlineMode = fontSize < 80;
    final mergeDist = centerlineMode 
        ? (fontSize * 0.12).clamp(8.0, 24.0) 
        : 10.0;
    
    // Vectorize the PNG using local OpenCV.js
    final strokes = await Vectorizer.vectorize(
      bytes: pngBytes,
      worldScale: 1.0,
      edgeMode: 'Canny',
      blurK: 3,
      cannyLo: 30,
      cannyHi: 120,
      epsilon: centerlineMode ? 0.6 : 0.8,
      resampleSpacing: centerlineMode ? 0.8 : 1.0,
      minPerimeter: 12.0,
      retrExternalOnly: false,
      angleThresholdDeg: 85,
      angleWindow: 3,
      smoothPasses: centerlineMode ? 2 : 1,
      mergeParallel: true,
      mergeMaxDist: mergeDist,
      minStrokeLen: 4.0,
      minStrokePoints: 3,
    );

    // Normalize stroke direction and order by x position
    final normalized = strokes.map((s) {
      if (s.isEmpty) return s;
      return s.first.dx <= s.last.dx ? s : s.reversed.toList();
    }).toList();
    normalized.sort((a, b) {
      final ax = a.map((p) => p.dx).reduce((x, y) => x < y ? x : y);
      final bx = b.map((p) => p.dx).reduce((x, y) => x < y ? x : y);
      return ax.compareTo(bx);
    });

    // Stitch nearby endpoints
    final stitched = _stitchStrokes(normalized, maxGap: (fontSize * 0.08).clamp(3.0, 18.0));
    
    // Apply world offset
    return stitched.map((s) => s.map((p) => p + worldOffset).toList()).toList();
  }

  /// Render text to PNG bytes using Flutter's TextPainter
  Future<Uint8List> _renderTextToPng(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    
    const pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );
    tp.paint(canvas, const Offset(pad, pad));
    
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// Stitch strokes with nearby endpoints
  List<List<Offset>> _stitchStrokes(List<List<Offset>> strokes, {double maxGap = 3.0}) {
    if (strokes.isEmpty) return strokes;
    final remaining = List<List<Offset>>.from(strokes);
    final out = <List<Offset>>[];
    var current = remaining.removeAt(0);
    
    while (remaining.isNotEmpty) {
      int bestIdx = -1;
      bool reverse = false;
      double best = maxGap;
      
      for (int i = 0; i < remaining.length; i++) {
        final s = remaining[i];
        final dStart = (s.first - current.last).distance;
        final dEnd = (s.last - current.last).distance;
        if (dStart < best) {
          best = dStart;
          bestIdx = i;
          reverse = false;
        }
        if (dEnd < best) {
          best = dEnd;
          bestIdx = i;
          reverse = true;
        }
      }
      
      if (bestIdx == -1) {
        out.add(current);
        current = remaining.removeAt(0);
      } else {
        var s = remaining.removeAt(bestIdx);
        if (reverse) s = s.reversed.toList();
        current = [...current, ...s];
      }
    }
    out.add(current);
    return out;
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


  /// Handle drawing actions from timeline
  ///
  /// Processes all action types: heading, bullet, subbullet, label, formula, sketch_image
  Future<void> handleDrawingActions(List<DrawingAction> actions) async {
    debugPrint('🎨 handleDrawingActions called with ${actions.length} actions');
    
    if (actions.isEmpty) {
      debugPrint('⚠️ No drawing actions to handle');
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
    
    for (int i = 0; i < actions.length; i++) {
      final action = actions[i];
      final textPreview = action.text.length > 30 
          ? '${action.text.substring(0, 30)}...' 
          : action.text;
      debugPrint('  [$i] Action type: ${action.type}, text: "$textPreview"');
      
      try {
        switch (action.type) {
          case 'heading':
          case 'bullet':
          case 'subbullet':
          case 'label':
          case 'formula':
            // All text-based actions
            final placement = action.placementValues;
            debugPrint('    → Adding text at (${placement.x}, ${placement.y})');
            await addText(
              text: action.text,
              origin: Offset(placement.x, placement.y),
              letterSize: (action.style?['fontSize'] as num?)?.toDouble() ?? 180.0,
            );
            debugPrint('    ✓ Text added');
            break;
            
          case 'sketch_image':
            // Image action - use ImageSketchService
            debugPrint('    → sketch_image action');
            final imageUrl = action.resolvedImageUrl;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              debugPrint('      URL: ${imageUrl.length > 50 ? '${imageUrl.substring(0, 50)}...' : imageUrl}');
            }
            // Note: Full sketch_image handling requires ImageSketchService integration
            // with layout state. For now, log the action.
            debugPrint('    ⚠️ sketch_image requires full layout integration');
            break;
            
          default:
            debugPrint('    ⚠️ Unknown action type: ${action.type}');
        }
      } catch (e, st) {
        debugPrint('    ❌ Error handling action: $e');
        debugPrint('    Stack: $st');
      }
    }
    
    debugPrint('🎨 handleDrawingActions completed');
  }
  
  /// Handle drawing actions with explicit duration (from dictation detection)
  ///
  /// This method is called by TimelinePlaybackController with the calculated
  /// draw duration based on dictation detection.
  Future<void> handleDrawingActionsWithDuration(
    List<DrawingAction> actions, 
    double drawDurationSeconds,
  ) async {
    debugPrint('🎨 handleDrawingActionsWithDuration: ${actions.length} actions, ${drawDurationSeconds.toStringAsFixed(1)}s');
    
    // TODO: Use drawDurationSeconds to set animation controller duration
    // For now, delegate to standard handler
    await handleDrawingActions(actions);
  }

  /// Erase object by name
  Future<void> eraseObject(String name) async {
    if (name.isEmpty) return;

    _staticStrokes = _staticStrokes.where((s) => s.jsonName != name).toList();
    _animStrokes = _animStrokes.where((s) => s.jsonName != name).toList();
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

    _status = 'Erased "$name". Remaining: ${allStrokes.length} strokes';
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
    _drawnObjectNames.clear();
    _selectedEraseName = null;
    _animValue = 0.0;
    _isAnimating = false;
    _status = 'Board cleared';
    notifyListeners();
  }

  /// Replay the current animation
  void replayAnimation() {
    if (_animStrokes.isEmpty) {
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
