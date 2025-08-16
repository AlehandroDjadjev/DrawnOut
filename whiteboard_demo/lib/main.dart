// lib/main.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'vectorizer.dart';
import 'assistant_api.dart';
import 'assistant_audio.dart';
import 'sdk_live_bridge.dart';
import 'planner.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vector Sketch Whiteboard',
      theme: ThemeData.light(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const WhiteboardPage(),
    );
  }
}

class PlacedImage {
  final ui.Image image;
  Offset worldCenter;
  Size worldSize;
  PlacedImage({required this.image, required this.worldCenter, required this.worldSize});
}

class StrokePlan {
  final List<List<Offset>> strokes;
  StrokePlan(this.strokes);
  bool get isEmpty => strokes.isEmpty;

  double totalLength() {
    double L = 0.0;
    for (final s in strokes) {
      for (int i = 1; i < s.length; i++) {
        L += (s[i] - s[i - 1]).distance;
      }
    }
    return L;
  }

  Path toPath() {
    final p = Path();
    for (final s in strokes) {
      if (s.isEmpty) continue;
      p.moveTo(s.first.dx, s.first.dy);
      for (int i = 1; i < s.length; i++) {
        p.lineTo(s[i].dx, s[i].dy);
      }
    }
    return p;
  }
}

/// A committed, persistent vector on the board (no raster).
class VectorObject {
  final StrokePlan plan;

  // Style frozen at commit-time
  final double baseWidth;
  final double passOpacity;
  final int passes;
  final double jitterAmp;
  final double jitterFreq;

  VectorObject({
    required this.plan,
    required this.baseWidth,
    required this.passOpacity,
    required this.passes,
    required this.jitterAmp,
    required this.jitterFreq,
  });
}


class SketchPlayer extends StatefulWidget {
  final StrokePlan plan;
  final double totalSeconds;
  final double baseWidth;
  final double passOpacity;
  final int passes;
  final double jitterAmp;
  final double jitterFreq;
  final bool showRasterUnderlay;
  final PlacedImage? raster;

  const SketchPlayer({
    super.key,
    required this.plan,
    required this.totalSeconds,
    this.baseWidth = 2.5,
    this.passOpacity = 0.8,
    this.passes = 2,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.02,
    this.showRasterUnderlay = true,
    this.raster,
  });

  @override
  State<SketchPlayer> createState() => _SketchPlayerState();
}

class _SketchPlayerState extends State<SketchPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late Path _fullPath;
  late double _totalLen;

  @override
  void initState() {
    super.initState();
    _fullPath = widget.plan.toPath();
    _totalLen = _computeTotalLen(_fullPath);
    _anim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.totalSeconds * 1000).round()),
    )..addListener(() => setState(() {}))
     ..forward();
  }

  @override
  void didUpdateWidget(covariant SketchPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan || oldWidget.totalSeconds != widget.totalSeconds) {
      _fullPath = widget.plan.toPath();
      _totalLen = _computeTotalLen(_fullPath);
      _anim.duration = Duration(milliseconds: (widget.totalSeconds * 1000).round());
      _anim..reset()..forward();
    }
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final progressLen = (_totalLen * _anim.value).clamp(0.0, _totalLen);
    final partial = _extractPartialPath(_fullPath, progressLen);

    return CustomPaint(
      painter: _SketchPainter(
        partialWorldPath: partial,
        raster: widget.showRasterUnderlay ? widget.raster : null,
        passes: widget.passes,
        passOpacity: widget.passOpacity,
        baseWidth: widget.baseWidth,
        jitterAmp: widget.jitterAmp,
        jitterFreq: widget.jitterFreq,
      ),
      isComplex: true,
    );
  }

  double _computeTotalLen(Path p) {
    double L = 0.0;
    for (final m in p.computeMetrics()) L += m.length;
    return L;
  }

  Path _extractPartialPath(Path p, double targetLen) {
    final out = Path();
    double acc = 0.0;
    for (final m in p.computeMetrics()) {
      if (acc >= targetLen) break;
      final remain = targetLen - acc;
      final take = remain >= m.length ? m.length : remain;
      if (take > 0) {
        out.addPath(m.extractPath(0, take), Offset.zero);
        acc += take;
      }
    }
    return out;
  }
}

class _SketchPainter extends CustomPainter {
  final Path partialWorldPath;
  final PlacedImage? raster;
  final int passes;
  final double passOpacity;
  final double baseWidth;
  final double jitterAmp;
  final double jitterFreq;

  const _SketchPainter({
    required this.partialWorldPath,
    required this.raster,
    required this.passes,
    required this.passOpacity,
    required this.baseWidth,
    required this.jitterAmp,
    required this.jitterFreq,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    final center = Offset(size.width / 2, size.height / 2);

    if (raster != null) {
      final p = raster!;
      final topLeft = center + p.worldCenter - Offset(p.worldSize.width / 2, p.worldSize.height / 2);
      final dest = topLeft & p.worldSize;
      final src = Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble());
      final imgPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withOpacity(1.0);
      canvas.drawImageRect(p.image, src, dest, imgPaint);
      final veil = Paint()..color = Colors.white.withOpacity(0.35);
      canvas.drawRect(dest, veil);
    }

    canvas.translate(center.dx, center.dy);

    for (int k = 0; k < passes; k++) {
      final seed = 1337 + k * 97;
      final noisy = _jitterPath(partialWorldPath, amp: jitterAmp, freq: jitterFreq, seed: seed);

      final paint = Paint()
        ..color = Colors.black.withOpacity((passOpacity).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (baseWidth * (1.0 + (k == 0 ? 0.0 : -0.15 * k))).clamp(0.5, 100.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(noisy, paint);
    }
  }

  Path _jitterPath(Path p, {required double amp, required double freq, required int seed}) {
    if (amp <= 0 || freq <= 0) return p;
    final rnd = math.Random(seed);
    final out = Path();
    for (final m in p.computeMetrics()) {
      final nSamples = (m.length * freq).clamp(8, 20000).toInt();
      for (int i = 0; i <= nSamples; i++) {
        final d = m.length * (i / nSamples);
        final pos = m.getTangentForOffset(d)!.position;
        final dx = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final dy = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final q = pos + Offset(dx, dy);
        if (i == 0) out.moveTo(q.dx, q.dy);
        else out.lineTo(q.dx, q.dy);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) {
    return old.partialWorldPath != partialWorldPath ||
           old.raster != raster ||
           old.passes != passes ||
           old.passOpacity != passOpacity ||
           old.baseWidth != baseWidth ||
           old.jitterAmp != jitterAmp ||
           old.jitterFreq != jitterFreq;
  }
}

/// Paints all committed vector objects (transparent background),
/// so we can layer it **on top** of the existing renderer without changing it.
class _CommittedPainter extends CustomPainter {
  final List<VectorObject> objects;
  const _CommittedPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);

    for (int i = 0; i < objects.length; i++) {
      final o = objects[i];
      _drawStyledPath(
        canvas,
        o.plan.toPath(),
        passes: o.passes,
        passOpacity: o.passOpacity,
        baseWidth: o.baseWidth,
        jitterAmp: o.jitterAmp,
        jitterFreq: o.jitterFreq,
        seedBase: 9001 + i * 67,
      );
    }
    canvas.restore();
  }

  void _drawStyledPath(
    Canvas canvas,
    Path path, {
    required int passes,
    required double passOpacity,
    required double baseWidth,
    required double jitterAmp,
    required double jitterFreq,
    required int seedBase,
  }) {
    for (int k = 0; k < passes; k++) {
      final noisy = _jitterPath(path, amp: jitterAmp, freq: jitterFreq, seed: seedBase + k * 97);
      final paint = Paint()
        ..color = Colors.black.withOpacity(passOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (baseWidth * (1.0 + (k == 0 ? 0.0 : -0.15 * k))).clamp(0.5, 100.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(noisy, paint);
    }
  }

  Path _jitterPath(Path p, {required double amp, required double freq, required int seed}) {
    if (amp <= 0 || freq <= 0) return p;
    final rnd = math.Random(seed);
    final out = Path();
    for (final m in p.computeMetrics()) {
      final nSamples = (m.length * freq).clamp(8, 20000).toInt();
      for (int i = 0; i <= nSamples; i++) {
        final d = m.length * (i / nSamples);
        final pos = m.getTangentForOffset(d)!.position;
        final dx = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final dy = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final q = pos + Offset(dx, dy);
        if (i == 0) out.moveTo(q.dx, q.dy);
        else out.lineTo(q.dx, q.dy);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _CommittedPainter old) => old.objects != objects;
}

class WhiteboardPage extends StatefulWidget {
  const WhiteboardPage({super.key});
  @override
  State<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends State<WhiteboardPage> {
  static const double canvasW = 1600; // fallback/default
  static const double canvasH = 1000; // fallback/default
  Size? _canvasSize;                   // live size from LayoutBuilder

  // NEW: persistent board of committed vectors
  final List<VectorObject> _board = [];

  Uint8List? _uploadedBytes;
  ui.Image? _uploadedImage;
  PlacedImage? _raster;
  StrokePlan? _plan;

  final _xCtrl = TextEditingController(text: '0');
  final _yCtrl = TextEditingController(text: '0');
  final _wCtrl = TextEditingController(text: '800');
  final _textCtrl = TextEditingController(text: 'Hello world');

  // --- Vectorizer defaults mirrored in UI ---
  String _edgeMode = 'Canny';
  double _blurK = 5;
  double _cannyLo = 50; // match defaults
  double _cannyHi = 160;
  double _dogSigma = 1.2;
  double _dogK = 1.6;
  double _dogThresh = 6.0;
  double _epsilon = 1.1187500000000001;
  double _resample = 1.410714285714286;
  double _minPerim = 19.839285714285793;
  bool _externalOnly = false;
  double _worldScale = 1.0;

  // Playback/style (unchanged)
  double _seconds = 60;
  int _passes = 1;
  double _opacity = 0.8;
  double _width = 5;
  double _jitterAmp = 0;
  double _jitterFreq = 0.02;
  bool _showRasterUnder = true;

  // Stroke shaping knobs (match defaults)
  double _angleThreshold = 30.0;  // deg
  double _angleWindow = 4;        // samples
  double _smoothPasses = 3;       // 0..3
  bool _mergeParallel = true;
  double _mergeMaxDist = 12.0;    // px/world
  double _minStrokeLen = 8.70;    // px/world
  double _minStrokePoints = 6;    // int

  bool _busy = false;
  double _textFontSize = 60.0;
  // Assistant
  final _apiUrlCtrl = TextEditingController(text: 'http://localhost:8000');
  AssistantApiClient? _api;
  int? _sessionId;
  final _questionCtrl = TextEditingController();
  // handled by assistant_audio on each platform
  bool _inLive = false;
  bool _wantLive = false;
  Timer? _autoNextTimer;
  // Orchestrator
  final _actionsCtrl = TextEditingController(text: '{\n  "whiteboard_actions": [\n    { "type": "heading", "text": "Sample Topic" },\n    { "type": "bullet", "level": 1, "text": "Key idea one" },\n    { "type": "bullet", "level": 1, "text": "Key idea two" }\n  ]\n}');

  // Layout state for orchestrator
  _LayoutState? _layout;
  // Adjustable layout config (defaults match code below)
  double _cfgMarginTop = 60, _cfgMarginRight = 64, _cfgMarginBottom = 60, _cfgMarginLeft = 64;
  double _cfgLineHeight = 1.25, _cfgGutterY = 14;
  double _cfgIndent1 = 32, _cfgIndent2 = 64, _cfgIndent3 = 96;
  double _cfgHeading = 60, _cfgBody = 60, _cfgTiny = 60;
  int _cfgColumnsCount = 1; double _cfgColumnsGutter = 48;
  // Centerline controls
  double _clThreshold = 60.0;            // px
  double _clEpsilon = 0.6;               // simplify tighter
  double _clResample = 0.8;              // denser sampling
  double _clMergeFactor = 0.9;           // merge distance = factor * font
  double _clMergeMin = 12.0;             // clamp
  double _clMergeMax = 36.0;             // clamp
  double _clSmoothPasses = 3.0;          // 0..4
  bool _preferOutlineHeadings = true;    // headings keep double outline
  bool _sketchPreferOutline = false;     // sketch text: default centerline

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void initState() {
    super.initState();
    // Mirror index.html end-of-segment behavior
    setAssistantOnQueueEmpty(() async {
      // If user pressed Raise Hand, start SDK live when the current segment ends
      if (_wantLive && !_inLive) {
        setState(() { _inLive = true; });
        await startSdkLive(oneTurn: false);
        return;
      }
      // Otherwise auto-advance after a short window
      if (!_inLive && _sessionId != null && _api != null) {
        try { _autoNextTimer?.cancel(); } catch (_) {}
        _autoNextTimer = Timer(const Duration(milliseconds: 1200), () async {
          try {
            final data = await _api!.nextSegment(_sessionId!);
            enqueueAssistantAudioFromSession(data);
          } catch (_) {}
        });
      }
    });
  }

  @override
  void dispose() {
    _xCtrl.dispose(); _yCtrl.dispose(); _wCtrl.dispose(); _textCtrl.dispose();
    _apiUrlCtrl.dispose(); _questionCtrl.dispose();
    try { _autoNextTimer?.cancel(); } catch (_) {}
    _actionsCtrl.dispose();
    disposeAssistantAudio();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showError('Could not load image data. Try a PNG or JPG.');
      return;
    }

    setState(() { _busy = true; });

    _uploadedBytes = bytes;
    _uploadedImage = await _decodeUiImage(bytes);

    final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
    final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
    final w = (double.tryParse(_wCtrl.text.trim()) ?? 800).clamp(1, 100000).toDouble();

    final aspect = _uploadedImage!.height / _uploadedImage!.width;
    final size = Size(w, w * aspect);
    _raster = PlacedImage(image: _uploadedImage!, worldCenter: Offset(x, y), worldSize: size);

    setState(() { _busy = false; _plan = null; });
  }

  Future<void> _vectorizeAndSketch() async {
    if (_uploadedBytes == null || _uploadedBytes!.isEmpty) {
      _showError('Please upload an image first.');
      return;
    }

    setState(() { _busy = true; });

    try {
      final strokes = await Vectorizer.vectorize(
        bytes: _uploadedBytes!,
        worldScale: _worldScale,
        edgeMode: _edgeMode,
        blurK: _blurK.toInt().isOdd ? _blurK.toInt() : _blurK.toInt()+1,
        cannyLo: _cannyLo,
        cannyHi: _cannyHi,
        dogSigma: _dogSigma,
        dogK: _dogK,
        dogThresh: _dogThresh,
        epsilon: _epsilon,
        resampleSpacing: _resample,
        minPerimeter: _minPerim,
        retrExternalOnly: _externalOnly,

        // Stroke shaping
        angleThresholdDeg: _angleThreshold,
        angleWindow: _angleWindow.round(),
        smoothPasses: _smoothPasses.round(),
        mergeParallel: _mergeParallel,
        mergeMaxDist: _mergeMaxDist,
        minStrokeLen: _minStrokeLen,
        minStrokePoints: _minStrokePoints.round(),
      );

      // IMPORTANT: do NOT resize. Only translate to the chosen (X, Y)
      // so the sketch animates exactly like before, just positioned.
      final offset = _raster?.worldCenter ?? Offset.zero;
      final placed = strokes
          .map((s) => s.map((p) => p + offset).toList())
          .toList();

      _plan = StrokePlan(placed);
    } catch (e, st) {
      debugPrint('Vectorize error: $e\n$st');
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  Future<Uint8List> _renderTextImageBytes(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
    tp.paint(canvas, Offset(pad, pad));
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  Future<void> _sketchText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _showError('Enter some text first.');
      return;
    }
    setState(() { _busy = true; });
    try {
      final png = await _renderTextImageBytes(text, _textFontSize);

      // Text-optimized vectorization parameters to reduce gaps and over-sketchiness
      final centerlineMode = !_sketchPreferOutline && _textFontSize < _clThreshold;
      final mergeDist = centerlineMode ? (_textFontSize * _clMergeFactor).clamp(_clMergeMin, _clMergeMax) : 10.0;
      final strokes = await Vectorizer.vectorize(
        bytes: png,
        worldScale: _worldScale,
        edgeMode: 'Canny',     // consistent edges for glyphs
        blurK: 3,               // light blur
        cannyLo: 30,
        cannyHi: 120,
        dogSigma: _dogSigma,
        dogK: _dogK,
        dogThresh: _dogThresh,
        epsilon: centerlineMode ? _clEpsilon : 0.8,
        resampleSpacing: centerlineMode ? _clResample : 1.0,
        minPerimeter: (_minPerim * 0.6).clamp(6.0, 1e9),
        retrExternalOnly: false,

        // Keep contours intact; avoid splitting curves aggressively
        angleThresholdDeg: 85,
        angleWindow: 3,
        smoothPasses: centerlineMode ? _clSmoothPasses.round() : 1,
        mergeParallel: true,
        mergeMaxDist: mergeDist,
        minStrokeLen: 4.0,
        minStrokePoints: 3,
      );

      // Normalize direction (left-to-right) and order strokes by leftmost x
      final normalized = strokes.map((s) {
        if (s.isEmpty) return s;
        return s.first.dx <= s.last.dx ? s : s.reversed.toList();
      }).toList();
      normalized.sort((a, b) {
        final ax = a.map((p) => p.dx).reduce(math.min);
        final bx = b.map((p) => p.dx).reduce(math.min);
        return ax.compareTo(bx);
      });

      // Stitch nearby endpoints to close small gaps, scaled by font size
      final stitched = _stitchStrokes(normalized, maxGap: (_textFontSize * 0.08).clamp(3.0, 18.0));

      final offset = _raster?.worldCenter ?? Offset.zero;
      final placed = stitched.map((s) => s.map((p) => p + offset).toList()).toList();
      _plan = StrokePlan(placed);
    } catch (e, st) {
      debugPrint('SketchText error: $e\n$st');
      _showError(e.toString());
    } finally {
      if (mounted) setState(() { _busy = false; });
    }
  }

  // Commit the current animated sketch to the board memory.
  void _commitCurrentSketch() {
    if (_plan == null) return;
    final obj = VectorObject(
      plan: _plan!,
      baseWidth: _width,
      passOpacity: _opacity,
      passes: _passes,
      jitterAmp: _jitterAmp,
      jitterFreq: _jitterFreq,
    );
    setState(() {
      _board.add(obj);
      _plan = null; // leave only the committed version
    });
  }

  // ========== Whiteboard Orchestrator ==========
  Future<void> _ensureLayout() async {
    _layout ??= _makeLayout();
  }

  _LayoutState _makeLayout() {
    final cfg = _buildLayoutConfigForSize(_canvasSize?.width ?? canvasW, _canvasSize?.height ?? canvasH);
    return _LayoutState(config: cfg, cursorY: cfg.page.top, columnIndex: 0, blocks: <_DrawnBlock>[], sectionCount: 0);
  }

  _LayoutConfig _buildLayoutConfigForSize(double w, double h) {
    final columns = (_cfgColumnsCount <= 1)
        ? null
        : _Columns(count: _cfgColumnsCount.clamp(1, 4), gutter: _cfgColumnsGutter);
    return _LayoutConfig(
      page: _Page(
        width: w, height: h,
        top: _cfgMarginTop, right: _cfgMarginRight, bottom: _cfgMarginBottom, left: _cfgMarginLeft,
      ),
      lineHeight: _cfgLineHeight,
      gutterY: _cfgGutterY,
      indent: _Indent(level1: _cfgIndent1, level2: _cfgIndent2, level3: _cfgIndent3),
      columns: columns,
      fonts: _Fonts(heading: _cfgHeading, body: _cfgBody, tiny: _cfgTiny),
    );
  }

  Map<String, dynamic> _parseJsonSafe(String src) {
    try { return src.isEmpty ? <String, dynamic>{} : (jsonDecode(src) as Map<String, dynamic>); } catch (_) { return <String, dynamic>{}; }
  }

  Future<void> _handleWhiteboardActions(List actions) async {
    final accum = <List<Offset>>[];
    for (final a in actions) {
      if (a is! Map) continue;
      final type = (a['type'] ?? '').toString();
      final text = (a['text'] ?? '').toString();
      final level = (a['level'] is num) ? (a['level'] as num).toInt() : 1;
      final style = a['style'] as Map<String, dynamic>?;
      await _placeBlock(_layout!, type: type, text: text, level: level, style: style, accum: accum);
    }
    if (accum.isNotEmpty) {
      setState(() { _plan = StrokePlan(accum); });
    }
  }

  Future<void> _runPlannerAndRender(Map<String, dynamic> sessionData) async {
    try {
      await _ensureLayout();
      final planner = WhiteboardPlanner(_apiUrlCtrl.text.trim().isEmpty ? 'http://127.0.0.1:8000' : _apiUrlCtrl.text.trim());
      final plan = await planner.planForSession(sessionData);
      if (plan == null) return;
      // Use the draw-JSON feature directly (paste equivalent) by feeding actions into our drawer
      final actions = (plan['whiteboard_actions'] as List?) ?? const [];
      await _handleWhiteboardActions(actions);
    } catch (_) {}
  }

  Future<void> _placeBlock(
    _LayoutState st, {
      required String type,
      required String text,
      int level = 1,
      Map<String, dynamic>? style,
      required List<List<Offset>> accum,
    }
  ) async {
    final cfg = st.config;
    final contentX0 = cfg.page.left + st._columnOffsetX();
    final contentW = st._columnWidth();

    final font = _chooseFont(type, cfg.fonts, style);
    final indent = _indentFor(type, level, cfg.indent);
    final maxWidth = (contentW - indent).clamp(80.0, contentW);
    final lines = _wrapText(text, font, maxWidth);
    final height = (lines.length * font * cfg.lineHeight).ceilToDouble();

    double x = contentX0 + indent;
    double y = st.cursorY;
    // clamp within content box
    if (x < contentX0) x = contentX0;
    final rightLimit = cfg.page.width - cfg.page.right;
    final maxX = rightLimit - 1.0;
    if (x > maxX) x = maxX;
    if (y < cfg.page.top) y = cfg.page.top;
    // collision/flow: push down if intersects
    y = _nextNonCollidingY(st, x, height, y);

    // overflow handling → new column/page
    if (y + height > (cfg.page.height - cfg.page.bottom)) {
      if (cfg.columns != null && st.columnIndex < (cfg.columns!.count - 1)) {
        st.columnIndex += 1;
        st.cursorY = cfg.page.top;
        await _placeBlock(st, type: type, text: text, level: level, style: style, accum: accum);
        return;
      } else {
        // new page: clear board and reset layout (simple approach)
        _board.clear();
        st.columnIndex = 0; st.cursorY = cfg.page.top; st.blocks.clear(); st.sectionCount += 1;
        await _placeBlock(st, type: type, text: text, level: level, style: style, accum: accum);
        return;
      }
    }

    // draw via sketch-text pipeline for consistent handwriting vibe
    // Convert content-space (pixels from top-left of canvas) to world-space (origin center)
    final worldTopLeft = Offset(x - (cfg.page.width/2), y - (cfg.page.height/2));
    final preferOutline = (type == 'heading' || type == 'formula');
    final strokes = await _drawTextLines(lines, worldTopLeft, font, preferOutline: preferOutline);
    accum.addAll(strokes);

    final bbox = _BBox(x: x, y: y, w: maxWidth, h: height);
    st.blocks.add(_DrawnBlock(id: 'b${st.blocks.length+1}', type: type, bbox: bbox, meta: {'level': level, 'text': text}));

    // advance cursor
    final extra = (type == 'heading') ? cfg.gutterY * 1.5 : cfg.gutterY;
    st.cursorY = y + height + extra;
  }

  Future<List<List<Offset>>> _drawTextLines(List<String> lines, Offset topLeftWorld, double fontSize, {bool preferOutline = false}) async {
    // Render each line as a text image → vectorize → place inside content box using top-left anchor
    final out = <List<Offset>>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i]; if (line.trim().isEmpty) continue;
      // Scale small fonts up for legibility and then scale back in world
      final scaleUp = fontSize < 24 ? (24.0 / fontSize) : 1.0;
      final rl = await _renderTextLine(line, fontSize * scaleUp);
      final centerlineMode = !preferOutline && fontSize < _clThreshold;
      final mergeDist = centerlineMode ? (fontSize * _clMergeFactor).clamp(_clMergeMin, _clMergeMax) : 10.0;
      final strokes = await Vectorizer.vectorize(
        bytes: rl.bytes,
        worldScale: _worldScale,
        edgeMode: 'Canny', blurK: 3, cannyLo: 30, cannyHi: 120,
        epsilon: centerlineMode ? _clEpsilon : 0.8,
        resampleSpacing: centerlineMode ? _clResample : 1.0,
        minPerimeter: (_minPerim * 0.6).clamp(6.0, 1e9), retrExternalOnly: false,
        angleThresholdDeg: 85, angleWindow: 3, smoothPasses: centerlineMode ? _clSmoothPasses.round() : 1,
        mergeParallel: true, mergeMaxDist: mergeDist,
        minStrokeLen: 4.0, minStrokePoints: 3,
      );
      final lineHeight = fontSize * 1.25;
      // Center-of-image placement: vectorizer returns strokes centered at (0,0) of the image
      final centerOffset = Offset(rl.w / 2.0, rl.h / 2.0);
      final offset = topLeftWorld + Offset(0, i * lineHeight) + centerOffset;
      // If we scaled up, scale down coordinates to match intended font size
      final placed = strokes.map((s) => s.map((p) => (p + offset) / scaleUp).toList()).toList();
      out.addAll(placed);
    }
    return out;
  }

  // Render a single line to PNG and return bytes with pixel size (used to convert top-left → center coords)
  Future<_RenderedLine> _renderTextLine(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
    tp.paint(canvas, Offset(pad, pad));
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return _RenderedLine(bytes: data!.buffer.asUint8List(), w: w.toDouble(), h: h.toDouble());
  }

  double _chooseFont(String type, _Fonts fonts, Map<String, dynamic>? style) {
    if (style != null && style['fontSize'] is num) return (style['fontSize'] as num).toDouble();
    if (type == 'heading') return fonts.heading;
    if (type == 'formula') return fonts.heading;
    return fonts.body;
  }

  double _indentFor(String type, int level, _Indent indent) {
    if (type == 'bullet') {
      if (level <= 1) return indent.level1;
      if (level == 2) return indent.level2;
      return indent.level3;
    }
    if (type == 'subbullet') {
      if (level <= 1) return indent.level2; if (level == 2) return indent.level3; return indent.level3 + 24;
    }
    return 0.0;
  }

  List<String> _wrapText(String text, double fontSize, double maxWidth) {
    // crude heuristic by average char width (~0.58em)
    final avg = fontSize * 0.55;
    final maxChars = math.max(8, (maxWidth / avg).floor());
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var cur = '';
    for (final w in words) {
      if (cur.isEmpty) { cur = w; continue; }
      if ((cur.length + 1 + w.length) <= maxChars) { cur += ' ' + w; }
      else { lines.add(cur); cur = w; }
    }
    if (cur.isNotEmpty) lines.add(cur);
    return lines;
  }

  double _nextNonCollidingY(_LayoutState st, double x, double h, double startY) {
    double y = startY;
    while (true) {
      bool hit = false;
      for (final b in st.blocks) {
        if (b.bbox.intersects(_BBox(x: x, y: y, w: b.bbox.w, h: h))) { y = b.bbox.bottom + st.config.gutterY; hit = true; break; }
      }
      if (!hit) return y;
      if (y > st.config.page.height - st.config.page.bottom) return y;
    }
  }

  // Simple post-process to connect stroke endpoints that are very close,
  // reducing visual gaps in contours.
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
        if (dStart < best) { best = dStart; bestIdx = i; reverse = false; }
        if (dEnd   < best) { best = dEnd;   bestIdx = i; reverse = true;  }
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

  void _clearBoard() {
    setState(() => _board.clear());
  }

  void _undoLast() {
    if (_board.isEmpty) return;
    setState(() => _board.removeLast());
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) async {
    final c = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) => c.complete(img));
    return c.future;
  }

  @override
  Widget build(BuildContext context) {
    final rightPanel = _buildRightPanel(context);

    // We layer committed objects on TOP so we don't change your existing renderer.
    Widget _buildCanvas(Size size) {
      // update layout page size to reflect live canvas
      _maybeUpdateCanvasSize(size);
      final baseCanvas = _busy
          ? const Center(child: CircularProgressIndicator())
          : (_plan == null
              ? CustomPaint(painter: _RasterOnlyPainter(raster: _raster))
              : SketchPlayer(
                  plan: _plan!,
                  totalSeconds: _seconds,
                  baseWidth: _width,
                  passOpacity: _opacity,
                  passes: _passes,
                  jitterAmp: _jitterAmp,
                  jitterFreq: _jitterFreq,
                  showRasterUnderlay: _showRasterUnder,
                  raster: _raster,
                ));
      return Stack(children: [
        Positioned.fill(child: baseCanvas),
        if (_board.isNotEmpty)
          Positioned.fill(child: CustomPaint(painter: _CommittedPainter(_board))),
      ]);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Vector Sketch Whiteboard'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'Undo last',
            onPressed: _board.isEmpty ? null : _undoLast,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Clear board',
            onPressed: _board.isEmpty ? null : _clearBoard,
            icon: const Icon(Icons.delete_sweep),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return _buildCanvas(size);
                },
              ),
            ),
            SizedBox(width: 360, child: rightPanel),
          ],
        ),
      ),
    );
  }

  void _maybeUpdateCanvasSize(Size size) {
    final prev = _canvasSize;
    if (prev != null && (prev.width - size.width).abs() < 1 && (prev.height - size.height).abs() < 1) return;
    _canvasSize = size;
    // rebuild layout config for new page size while preserving cursor/blocks
    if (_layout == null) return;
    final newCfg = _buildLayoutConfigForSize(size.width, size.height);
    setState(() {
      _layout = _LayoutState(
        config: newCfg,
        cursorY: _layout!.cursorY.clamp(newCfg.page.top, newCfg.page.height - newCfg.page.bottom),
        columnIndex: 0,
        blocks: _layout!.blocks, // keep drawn blocks references
        sectionCount: _layout!.sectionCount,
      );
    });
  }

  Widget _buildRightPanel(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: ListView(
        children: [
          Text('Source', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _pickImage,
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload Image'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 24),
          Text('Orchestrator Layout', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Heading size', 18, 72, _cfgHeading, (v) => setState(() => _cfgHeading = v)),
          _slider('Body size', 14, 48, _cfgBody, (v) => setState(() => _cfgBody = v)),
          _slider('Line height', 1.0, 1.8, _cfgLineHeight, (v) => setState(() => _cfgLineHeight = double.parse(v.toStringAsFixed(2)))),
          _slider('Gutter Y', 4, 40, _cfgGutterY, (v) => setState(() => _cfgGutterY = v)),
          _slider('Indent L1', 16, 120, _cfgIndent1, (v) => setState(() => _cfgIndent1 = v)),
          _slider('Indent L2', 32, 180, _cfgIndent2, (v) => setState(() => _cfgIndent2 = v)),
          _slider('Indent L3', 48, 240, _cfgIndent3, (v) => setState(() => _cfgIndent3 = v)),
          _slider('Margin Top', 0, 200, _cfgMarginTop, (v) => setState(() => _cfgMarginTop = v)),
          _slider('Margin Right', 0, 200, _cfgMarginRight, (v) => setState(() => _cfgMarginRight = v)),
          _slider('Margin Bottom', 0, 200, _cfgMarginBottom, (v) => setState(() => _cfgMarginBottom = v)),
          _slider('Margin Left', 0, 200, _cfgMarginLeft, (v) => setState(() => _cfgMarginLeft = v)),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _cfgColumnsCount,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 column')),
                  DropdownMenuItem(value: 2, child: Text('2 columns')),
                ],
                onChanged: (v) => setState(() => _cfgColumnsCount = v ?? 1),
                decoration: const InputDecoration(labelText: 'Columns'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _slider('Col. gutter', 0, 120, _cfgColumnsGutter, (v) => setState(() => _cfgColumnsGutter = v))),
          ]),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () {
                  setState(() {
                    _board.clear(); _plan = null; _layout = _makeLayout();
                  });
                },
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('Apply Layout (clear page)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () {
                  setState(() { if (_layout != null) _layout!.cursorY = _layout!.config.page.top; });
                },
                icon: const Icon(Icons.vertical_align_top),
                label: const Text('Reset Cursor'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('Centerline (Body Text)', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Centerline threshold (px)', 20, 120, _clThreshold, (v) => setState(() => _clThreshold = v)),
          _slider('Centerline epsilon', 0.3, 1.2, _clEpsilon, (v) => setState(() => _clEpsilon = double.parse(v.toStringAsFixed(2)))),
          _slider('Centerline resample', 0.5, 1.5, _clResample, (v) => setState(() => _clResample = double.parse(v.toStringAsFixed(2)))),
          _slider('Merge factor', 0.3, 1.6, _clMergeFactor, (v) => setState(() => _clMergeFactor = double.parse(v.toStringAsFixed(2)))),
          Row(children: [
            Expanded(child: _slider('Merge min', 4, 40, _clMergeMin, (v) => setState(() => _clMergeMin = v))),
            const SizedBox(width: 8),
            Expanded(child: _slider('Merge max', 8, 60, _clMergeMax, (v) => setState(() => _clMergeMax = v))),
          ]),
          _slider('Smooth passes', 0, 4, _clSmoothPasses, (v) => setState(() => _clSmoothPasses = v), divisions: 4, display: (v) => v.toStringAsFixed(0)),
          SwitchListTile(
            value: _preferOutlineHeadings,
            onChanged: (v) => setState(() => _preferOutlineHeadings = v),
            title: const Text('Headings keep outline (double stroke)'),
            dense: true,
          ),
          const Divider(height: 24),
          Text('Whiteboard Orchestrator', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _actionsCtrl,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Paste actions JSON',
              hintText: '{ "whiteboard_actions": [ {"type":"heading","text":"..."} ] }',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () async {
                  setState(() { _busy = true; });
                  try {
                    await _ensureLayout();
                    final map = _parseJsonSafe(_actionsCtrl.text.trim());
                    final list = (map['whiteboard_actions'] as List?) ?? const [];
                    await _handleWhiteboardActions(list);
                  } catch (e) { _showError(e.toString()); }
                  finally { if (mounted) setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('Render Actions'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () { setState(() { _layout = null; _board.clear(); _plan = null; }); },
                icon: const Icon(Icons.refresh),
                label: const Text('Clear & Reset Layout'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('AI Tutor', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _apiUrlCtrl,
            decoration: const InputDecoration(labelText: 'Backend URL (e.g. http://localhost:8000)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () async {
                  setState(() { _busy = true; });
                  try {
                    _api = AssistantApiClient(_apiUrlCtrl.text.trim());
                    setAssistantAudioBaseUrl(_apiUrlCtrl.text.trim());
                    final data = await _api!.startLesson(topic: 'Handwriting practice');
                    _sessionId = data['id'] as int?;
                    enqueueAssistantAudioFromSession(data);
                    await _runPlannerAndRender(data);
                    setState(() { _inLive = false; _wantLive = false; });
                  } catch (e) {
                    _showError(e.toString());
                  } finally { setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.play_circle),
                label: const Text('Start Lesson'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy || _sessionId == null ? null : () async {
                  setState(() { _busy = true; });
                  try {
                    final data = await _api!.nextSegment(_sessionId!);
                    enqueueAssistantAudioFromSession(data);
                    await _runPlannerAndRender(data);
                    setState(() { _inLive = false; _wantLive = false; });
                  } catch (e) { _showError(e.toString()); }
                  finally { setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.skip_next),
                label: const Text('Next'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _questionCtrl,
            decoration: const InputDecoration(labelText: 'Ask a question'),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || _sessionId == null ? null : () async {
                  setState(() { _busy = true; });
                  try {
                    final data = await _api!.raiseHand(_sessionId!, question: _questionCtrl.text.trim());
                    enqueueAssistantAudioFromSession(data);
                    // Do not start live immediately; mirror template: start at end of current segment
                    setState(() { _wantLive = true; });
                    await _runPlannerAndRender(data);
                  } catch (e) { _showError(e.toString()); }
                  finally { setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.record_voice_over),
                label: const Text('Ask'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy || _sessionId == null || _inLive ? null : () async {
                  // Raise hand for live: start live when current segment ends
                  setState(() { _wantLive = true; });
                  try { _autoNextTimer?.cancel(); } catch (_) {}
                },
                icon: const Icon(Icons.back_hand),
                label: const Text('Raise Hand (Live)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy || !_inLive || _sessionId == null ? null : () async {
                  setState(() { _busy = true; });
                  try {
                    await stopSdkLive();
                    setState(() { _inLive = false; _wantLive = false; });
                    if (_api != null && _sessionId != null) {
                      final data = await _api!.nextSegment(_sessionId!);
                      enqueueAssistantAudioFromSession(data);
                    }
                  } catch (e) { _showError(e.toString()); }
                  finally { setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.stop_circle),
                label: const Text('Stop Live & Next'),
              ),
            ),
          ]),
          const Divider(height: 24),
          Text('Text', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            decoration: const InputDecoration(labelText: 'Enter text'),
          ),
          _slider('Font size (px)', 20.0, 400.0, _textFontSize, (v) => setState(() => _textFontSize = v)),
          SwitchListTile(
            value: _sketchPreferOutline,
            onChanged: (v) => setState(() => _sketchPreferOutline = v),
            title: const Text('Prefer outline for Sketch Text'),
            dense: true,
          ),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _sketchText,
                icon: const Icon(Icons.draw),
                label: const Text('Sketch Text'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Placement (world coords, origin center)', style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _numField(_xCtrl, 'X')),
              const SizedBox(width: 8),
              Expanded(child: _numField(_yCtrl, 'Y')),
            ],
          ),
          const SizedBox(height: 8),
          _numField(_wCtrl, 'Width'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy || _uploadedImage == null ? null : () {
                    final x = double.tryParse(_xCtrl.text.trim()) ?? 0;
                    final y = double.tryParse(_yCtrl.text.trim()) ?? 0;
                    final w = (double.tryParse(_wCtrl.text.trim()) ?? 800).clamp(1, 100000).toDouble();
                    if (_uploadedImage != null) {
                      final aspect = _uploadedImage!.height / _uploadedImage!.width;
                      final size = Size(w, w * aspect);
                      setState(() {
                        _raster = PlacedImage(image: _uploadedImage!, worldCenter: Offset(x, y), worldSize: size);
                      });
                    }
                  },
                  icon: const Icon(Icons.my_location),
                  label: const Text('Apply Placement'),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          Text('Vectorization', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _edgeMode,
            items: const [
              DropdownMenuItem(value: 'Canny', child: Text('Canny')),
              DropdownMenuItem(value: 'DoG', child: Text('DoG (Difference of Gaussians)')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _edgeMode = v ?? 'Canny'),
            decoration: const InputDecoration(labelText: 'Edge Mode'),
          ),
          const SizedBox(height: 8),

          _slider('Gaussian ksize', 3, 13, _blurK, (v) => setState(() => _blurK = v.roundToDouble()), divisions: 5, display: (v) => v.round().toString()),
          if (_edgeMode == 'Canny') ...[
            _slider('Canny low', 10, 200, _cannyLo, (v) => setState(() => _cannyLo = v), divisions: 19),
            _slider('Canny high', 40, 300, _cannyHi, (v) => setState(() => _cannyHi = v), divisions: 26),
          ] else ...[
            _slider('DoG sigma', 0.6, 3.0, _dogSigma, (v) => setState(() => _dogSigma = v)),
            _slider('DoG k (sigma2 = k*sigma)', 1.2, 2.2, _dogK, (v) => setState(() => _dogK = v)),
            _slider('DoG threshold', 1.0, 30.0, _dogThresh, (v) => setState(() => _dogThresh = v)),
          ],
          _slider('Simplify epsilon (px)', 0.5, 6.0, _epsilon, (v) => setState(() => _epsilon = v)),
          _slider('Resample spacing (px)', 1.0, 6.0, _resample, (v) => setState(() => _resample = v)),
          _slider('Min perimeter (px)', 10.0, 300.0, _minPerim, (v) => setState(() => _minPerim = v)),
          _slider('World scale (px → world)', 0.3, 3.0, _worldScale, (v) => setState(() => _worldScale = v)),
          SwitchListTile(
            value: _externalOnly,
            onChanged: _busy ? null : (v) => setState(() => _externalOnly = v),
            title: const Text('External contours only'),
            dense: true,
          ),

          const Divider(height: 24),
          Text('Stroke shaping', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Angle threshold (deg)', 0.0, 90.0, _angleThreshold, (v) => setState(() => _angleThreshold = v), divisions: 90, display: (v) => v.toStringAsFixed(0)),
          _slider('Angle window (samples)', 1, 6, _angleWindow, (v) => setState(() => _angleWindow = v), divisions: 5, display: (v) => v.toStringAsFixed(0)),
          _slider('Smoothing passes', 0, 3, _smoothPasses, (v) => setState(() => _smoothPasses = v.roundToDouble()), divisions: 3, display: (v) => v.toStringAsFixed(0)),
          SwitchListTile(
            value: _mergeParallel,
            onChanged: (v) => setState(() => _mergeParallel = v),
            title: const Text('Merge parallel outlines'),
            dense: true,
          ),
          _slider('Merge max distance', 1.0, 12.0, _mergeMaxDist, (v) => setState(() => _mergeMaxDist = v)),
          _slider('Min stroke length', 4.0, 60.0, _minStrokeLen, (v) => setState(() => _minStrokeLen = v)),
          _slider('Min stroke points', 2, 20, _minStrokePoints, (v) => setState(() => _minStrokePoints = v), divisions: 18, display: (v) => v.toStringAsFixed(0)),

          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _busy || _uploadedBytes == null ? null : _vectorizeAndSketch,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Vectorize & Draw'),
          ),

          // NEW: Board actions
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _plan == null ? null : _commitCurrentSketch,
                icon: const Icon(Icons.push_pin),
                label: const Text('Commit current sketch'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _board.isEmpty ? null : _undoLast,
                icon: const Icon(Icons.undo),
                label: const Text('Undo last'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _board.isEmpty ? null : _clearBoard,
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear board'),
              ),
            ),
          ]),

          const Divider(height: 24),
          Text('Playback / Texture', style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          _slider('Total time (s)', 1.0, 30.0, _seconds, (v) => setState(() => _seconds = v), divisions: 29, display: (v) => '${v.toStringAsFixed(0)}s'),
          _slider('Base width', 0.5, 8.0, _width, (v) => setState(() => _width = v)),
          _slider('Passes', 1, 4, _passes.toDouble(), (v) => setState(() => _passes = v.round()), divisions: 3, display: (v) => v.round().toString()),
          _slider('Pass opacity', 0.2, 1.0, _opacity, (v) => setState(() => _opacity = v)),
          _slider('Jitter amp', 0.0, 3.0, _jitterAmp, (v) => setState(() => _jitterAmp = v)),
          _slider('Jitter freq', 0.005, 0.08, _jitterFreq, (v) => setState(() => _jitterFreq = v)),

          // Log everything
          ElevatedButton.icon(
            onPressed: () {
              debugPrint('--- CURRENT SETTINGS ---');
              debugPrint('edgeMode: $_edgeMode');
              debugPrint('blurK: $_blurK');
              debugPrint('cannyLo: $_cannyLo');
              debugPrint('cannyHi: $_cannyHi');
              debugPrint('dogSigma: $_dogSigma');
              debugPrint('dogK: $_dogK');
              debugPrint('dogThresh: $_dogThresh');
              debugPrint('epsilon: $_epsilon');
              debugPrint('resample: $_resample');
              debugPrint('minPerim: $_minPerim');
              debugPrint('worldScale: $_worldScale');
              debugPrint('externalOnly: $_externalOnly');

              debugPrint('angleThresholdDeg: $_angleThreshold');
              debugPrint('angleWindow: ${_angleWindow.round()}');
              debugPrint('smoothPasses: ${_smoothPasses.round()}');
              debugPrint('mergeParallel: $_mergeParallel');
              debugPrint('mergeMaxDist: $_mergeMaxDist');
              debugPrint('minStrokeLen: $_minStrokeLen');
              debugPrint('minStrokePoints: ${_minStrokePoints.round()}');

              debugPrint('seconds: $_seconds');
              debugPrint('passes: $_passes');
              debugPrint('opacity: $_opacity');
              debugPrint('width: $_width');
              debugPrint('jitterAmp: $_jitterAmp');
              debugPrint('jitterFreq: $_jitterFreq');
              debugPrint('showRasterUnder: $_showRasterUnder');

              debugPrint('placementX: ${_xCtrl.text}');
              debugPrint('placementY: ${_yCtrl.text}');
              debugPrint('placementWidth: ${_wCtrl.text}');
              debugPrint('------------------------');
            },
            icon: const Icon(Icons.bug_report),
            label: const Text('Log Current Settings'),
          ),

          SwitchListTile(
            value: _showRasterUnder,
            onChanged: (v) => setState(() => _showRasterUnder = v),
            title: const Text('Show raster under sketch'),
            dense: true,
          ),
        ],
      ),
    );
  }

  // (removed old direct-audio helper; playback handled by assistant_audio)

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _slider(String label, double min, double max, double value, ValueChanged<double> onChanged,
      {int? divisions, String Function(double)? display}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(display != null ? display(value) : value.toStringAsFixed((max - min) <= 10 ? 0 : 2)),
        ]),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value.clamp(min, max),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _RasterOnlyPainter extends CustomPainter {
  final PlacedImage? raster;
  const _RasterOnlyPainter({this.raster});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    if (raster == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final p = raster!;
    final topLeft = center + p.worldCenter - Offset(p.worldSize.width / 2, p.worldSize.height / 2);
    final dest = topLeft & p.worldSize;
    final src = Rect.fromLTWH(0, 0, p.image.width.toDouble(), p.image.height.toDouble());
    final imgPaint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(p.image, src, dest, imgPaint);
  }

  @override
  bool shouldRepaint(covariant _RasterOnlyPainter oldDelegate) => oldDelegate.raster != raster;
}

// ===== Orchestrator layout types =====
class _RenderedLine { final Uint8List bytes; final double w, h; _RenderedLine({required this.bytes, required this.w, required this.h}); }
class _LayoutConfig {
  final _Page page;
  final double lineHeight;
  final double gutterY;
  final _Indent indent;
  final _Columns? columns;
  final _Fonts fonts;
  const _LayoutConfig({
    required this.page,
    required this.lineHeight,
    required this.gutterY,
    required this.indent,
    required this.columns,
    required this.fonts,
  });
}

class _Page { final double width, height, top, right, bottom, left; const _Page({required this.width, required this.height, required this.top, required this.right, required this.bottom, required this.left}); }
class _Indent { final double level1, level2, level3; const _Indent({required this.level1, required this.level2, required this.level3}); }
class _Columns { final int count; final double gutter; const _Columns({required this.count, required this.gutter}); }
class _Fonts { final double heading, body, tiny; const _Fonts({required this.heading, required this.body, required this.tiny}); }

class _BBox {
  final double x, y, w, h;
  const _BBox({required this.x, required this.y, required this.w, required this.h});
  double get right => x + w;
  double get bottom => y + h;
  bool intersects(_BBox other) {
    return !(other.x >= right || other.right <= x || other.y >= bottom || other.bottom <= y);
  }
}

class _DrawnBlock { final String id; final String type; final _BBox bbox; final Map<String, dynamic>? meta; _DrawnBlock({required this.id, required this.type, required this.bbox, this.meta}); }

class _LayoutState {
  final _LayoutConfig config;
  double cursorY;
  int columnIndex;
  final List<_DrawnBlock> blocks;
  int sectionCount;
  _LayoutState({required this.config, required this.cursorY, required this.columnIndex, required this.blocks, required this.sectionCount});

  double _columnOffsetX() {
    if (config.columns == null) return 0.0;
    final cw = _columnWidth();
    return columnIndex * cw + columnIndex * config.columns!.gutter;
  }

  double _columnResidual() {
    if (config.columns == null) return 0.0;
    final total = (config.columns!.count - 1) * config.columns!.gutter + (config.columns!.count - 1) * _columnWidth();
    final used = columnIndex * config.columns!.gutter + columnIndex * _columnWidth();
    return total - used;
  }

  double _columnWidth() {
    if (config.columns == null) return config.page.width - config.page.left - config.page.right;
    final usable = config.page.width - config.page.left - config.page.right - (config.columns!.count - 1) * config.columns!.gutter;
    return usable / config.columns!.count;
  }

  static _LayoutState defaultConfig(double pageW, double pageH) {
    final cfg = _LayoutConfig(
      page: _Page(width: pageW, height: pageH, top: 60, right: 64, bottom: 60, left: 64),
      lineHeight: 1.25,
      gutterY: 14,
      indent: const _Indent(level1: 32, level2: 64, level3: 96),
      columns: null,
      fonts: const _Fonts(heading: 30, body: 22, tiny: 18),
    );
    return _LayoutState(config: cfg, cursorY: cfg.page.top, columnIndex: 0, blocks: <_DrawnBlock>[], sectionCount: 0);
  }
}
