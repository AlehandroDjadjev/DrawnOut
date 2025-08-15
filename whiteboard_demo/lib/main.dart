// lib/main.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'vectorizer.dart';
import 'assistant_api.dart';
import 'package:just_audio/just_audio.dart';

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
  static const double canvasW = 1600;
  static const double canvasH = 1000;

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
  double _seconds = 6;
  int _passes = 2;
  double _opacity = 0.8;
  double _width = 3;
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
  double _textFontSize = 160.0;
  // Assistant
  final _apiUrlCtrl = TextEditingController(text: 'http://localhost:8000');
  AssistantApiClient? _api;
  int? _sessionId;
  final _questionCtrl = TextEditingController();
  final _player = AudioPlayer();

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _xCtrl.dispose(); _yCtrl.dispose(); _wCtrl.dispose(); _textCtrl.dispose();
    _apiUrlCtrl.dispose(); _questionCtrl.dispose(); _player.dispose();
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
        epsilon: 0.8,           // tighter approximation
        resampleSpacing: 1.0,   // denser sampling to avoid tiny breaks
        minPerimeter: (_minPerim * 0.6).clamp(6.0, 1e9),
        retrExternalOnly: false,

        // Keep contours intact; avoid splitting curves aggressively
        angleThresholdDeg: 85,
        angleWindow: 3,
        smoothPasses: 1,
        mergeParallel: true,    // centerline for more handwriting-like strokes
        mergeMaxDist: 10.0,
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
              child: Center(
                child: SizedBox(
                  width: canvasW,
                  height: canvasH,
                  child: Stack(
                    children: [
                      Positioned.fill(child: baseCanvas),
                      // Committed vectors on top (transparent bg)
                      if (_board.isNotEmpty)
                        Positioned.fill(child: CustomPaint(painter: _CommittedPainter(_board))),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 360, child: rightPanel),
          ],
        ),
      ),
    );
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
                    final data = await _api!.startLesson(topic: 'Handwriting practice');
                    _sessionId = data['id'] as int?;
                    await _maybePlayLastTutorAudio(data);
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
                    await _maybePlayLastTutorAudio(data);
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
                    await _maybePlayLastTutorAudio(data);
                  } catch (e) { _showError(e.toString()); }
                  finally { setState(() { _busy = false; }); }
                },
                icon: const Icon(Icons.record_voice_over),
                label: const Text('Ask'),
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

  Future<void> _maybePlayLastTutorAudio(Map<String, dynamic> sessionData) async {
    try {
      final utterances = (sessionData['utterances'] as List?) ?? const [];
      if (utterances.isEmpty) return;
      // find last tutor utterance with audio_file
      for (var i = utterances.length - 1; i >= 0; i--) {
        final u = utterances[i] as Map;
        if (u['role'] == 'tutor' && (u['audio_file'] ?? '').toString().isNotEmpty) {
          final url = u['audio_file'].toString();
          await _player.setUrl(url);
          await _player.play();
          break;
        }
      }
    } catch (_) {}
  }

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
