// lib/main.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

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

class Vectorizer {
  static Future<List<List<Offset>>> vectorize({
    required Uint8List bytes,
    double worldScale = 1.0,
    String edgeMode = 'Canny',    // 'Canny' or 'DoG'
    int blurK = 5,                // odd
    double cannyLo = 50,
    double cannyHi = 160,
    double dogSigma = 1.2,
    double dogK = 1.6,
    double dogThresh = 6.0,
    double epsilon =  1.1187500000000001,
    double resampleSpacing = 1.410714285714286,
    double minPerimeter = 19.839285714285793,
    bool retrExternalOnly = true,

    // NEW knobs
    double angleThresholdDeg = 30,
    int angleWindow = 4,              // samples for windowed angle
    int smoothPasses = 3,             // 0..3
    bool mergeParallel = true,
    double mergeMaxDist = 12.0,       // px/world units
    double minStrokeLen = 8.70,       // px/world units
    int minStrokePoints = 6,          // drop tiny fragments
  }) async {
    if (bytes.isEmpty) {
      throw StateError('No image bytes provided.');
    }

    // 1) Decode to Mat (BGR) and prefilter
    final src = cv.imdecode(bytes, cv.IMREAD_COLOR);

    // Guard: imdecode failed → empty Mat
    if (src.cols == 0 || src.rows == 0) {
      src.dispose();
      throw StateError(
        'Failed to decode image (unsupported/empty data). '
        'Try PNG or JPEG (avoid HEIC/WEBP on Windows).',
      );
    }

    final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);

    // Ensure blurK is odd and >= 3
    final oddBlurK = (blurK.isOdd ? blurK : blurK + 1).clamp(3, 99);

    // Soft blur to reduce speckle before edges
    final blur = cv.gaussianBlur(gray, (oddBlurK, oddBlurK), 0);

    // 2) Edge map
    cv.Mat edge;
    if (edgeMode == 'DoG') {
      final g1 = cv.gaussianBlur(gray, (0, 0), dogSigma);
      final g2 = cv.gaussianBlur(gray, (0, 0), dogSigma * dogK);
      final diff = cv.subtract(g1, g2);            // signed DoG
      final absd = cv.convertScaleAbs(diff);       // uint8 |DoG|
      final (_, th) = cv.threshold(absd, dogThresh, 255, cv.THRESH_BINARY);
      edge = th;
      g1.dispose(); g2.dispose(); diff.dispose(); absd.dispose();
    } else {
      edge = cv.canny(blur, cannyLo, cannyHi);
    }

    // 3) Contours
    final mode = retrExternalOnly ? cv.RETR_EXTERNAL : cv.RETR_LIST;
    final (contours, _) = cv.findContours(edge, mode, cv.CHAIN_APPROX_NONE);

    // 4) Build stroke candidates (in world coords, origin center)
    final imgW = src.cols, imgH = src.rows;
    final cx = imgW / 2.0, cy = imgH / 2.0;

    final rawStrokes = <List<Offset>>[];

    for (final cnt in contours) {
      final peri = cv.arcLength(cnt, false);
      if (peri < minPerimeter) continue;

      final approx = cv.approxPolyDP(cnt, epsilon, false);
      // resample in image coords (top-left origin)
      final polyImg = _resampleCv(approx, spacing: resampleSpacing);
      if (polyImg.length < 2) continue;

      // to world coords (center origin)
      var polyWorld = polyImg
          .map((p) => Offset((p.dx - cx) * worldScale, (p.dy - cy) * worldScale))
          .toList();

      // smoothing passes to preserve circles/curves
      if (smoothPasses > 0) {
        polyWorld = _smoothPolyline(polyWorld, passes: smoothPasses);
      }

      // split by angle with window to avoid noisy splits on curves
      final parts = _splitByAngleWindow(
        polyWorld,
        thresholdDeg: angleThresholdDeg,
        window: angleWindow,
        minSegmentLen: minStrokeLen,
        minPoints: minStrokePoints,
      );

      for (final s in parts) {
        if (s.length >= minStrokePoints && _polyLen(s) >= minStrokeLen) {
          rawStrokes.add(s);
        }
      }
    }

    // 5) Merge near-parallel duplicate outlines into a single centerline
    final merged = mergeParallel
        ? _mergeParallelStrokes(rawStrokes,
            maxDist: mergeMaxDist,
            maxAngleDiffDeg: 12.0,
            minOverlapFrac: 0.45)
        : rawStrokes;

    // 6) Sort left-to-right then by length desc, then greedy endpoint order
    merged.sort((a, b) {
      final minAx = a.map((p) => p.dx).reduce(math.min);
      final minBx = b.map((p) => p.dx).reduce(math.min);
      if (minAx != minBx) return minAx.compareTo(minBx);
      final lenA = _polyLen(a), lenB = _polyLen(b);
      return lenB.compareTo(lenA);
    });
    final ordered = _orderGreedy(merged);

    // Cleanup
    src.dispose(); gray.dispose(); blur.dispose(); edge.dispose();

    return ordered;
  }

  // --- Helpers ----------------------------------------------------------------

  // Resample cv.VecPoint to evenly spaced Offsets (image coords)
  static List<Offset> _resampleCv(cv.VecPoint pts, {required double spacing}) {
    if (pts.length == 0) return const [];
    final out = <Offset>[];
    Offset prev = Offset(pts[0].x.toDouble(), pts[0].y.toDouble());
    out.add(prev);
    double acc = 0.0;
    for (int i = 1; i < pts.length; i++) {
      final cur = Offset(pts[i].x.toDouble(), pts[i].y.toDouble());
      final seg = (cur - prev).distance;
      if (seg < 1e-6) continue;
      final dir = (cur - prev) / seg;
      double remain = seg;
      while (acc + remain >= spacing) {
        final t = (spacing - acc);
        prev = prev + dir * t;
        out.add(prev);
        remain -= t;
        acc = 0.0;
      }
      acc += remain;
      prev = cur;
    }
    if ((out.last - prev).distance > 1e-3) out.add(prev);
    return out;
  }

  // Simple corner-preserving smoothing (Chaikin-like / tri-weight), repeated
  static List<Offset> _smoothPolyline(List<Offset> pts, {int passes = 1}) {
    if (pts.length < 3 || passes <= 0) return pts;
    var a = List<Offset>.from(pts);
    for (int p = 0; p < passes; p++) {
      final b = List<Offset>.from(a);
      for (int i = 1; i < a.length - 1; i++) {
        final prev = a[i - 1];
        final cur = a[i];
        final next = a[i + 1];
        b[i] = Offset(
          (prev.dx + 2 * cur.dx + next.dx) / 4.0,
          (prev.dy + 2 * cur.dy + next.dy) / 4.0,
        );
      }
      a = b;
    }
    return a;
  }

  // Windowed angle split to avoid false breaks on noisy curves
  static List<List<Offset>> _splitByAngleWindow(
    List<Offset> pts, {
    required double thresholdDeg,
    required int window,
    required double minSegmentLen,
    required int minPoints,
  }) {
    if (pts.length < 3) return [pts];
    final w = window.clamp(1, 20);
    final threshRad = thresholdDeg * math.pi / 180.0;

    final segs = <List<Offset>>[];
    var cur = <Offset>[pts.first];
    double curLen = 0.0;

    // Precompute segment lengths
    final segLen = List<double>.filled(pts.length, 0.0);
    for (int i = 1; i < pts.length; i++) {
      segLen[i] = (pts[i] - pts[i - 1]).distance;
    }

    for (int i = 1; i < pts.length - 1; i++) {
      cur.add(pts[i]);
      curLen += segLen[i];

      final i0 = (i - w).clamp(0, pts.length - 1);
      final i1 = (i + w).clamp(0, pts.length - 1);
      final v1 = pts[i] - pts[i0];
      final v2 = pts[i1] - pts[i];
      final ang = _angleBetween(v1, v2).abs();

      final shouldSplit = (ang > threshRad) &&
          (curLen >= minSegmentLen || cur.length >= minPoints);

      if (shouldSplit) {
        // finalize current
        if (cur.length >= 2) segs.add(cur);
        cur = [pts[i]];
        curLen = 0.0;
      }
    }
    cur.add(pts.last);
    if (cur.length >= 2) segs.add(cur);

    // Filter tiny segments
    return segs
        .where((s) => s.length >= minPoints && _polyLen(s) >= minSegmentLen)
        .toList();
  }

  static double _angleBetween(Offset a, Offset b) {
    final dot = a.dx * b.dx + a.dy * b.dy;
    final ma = a.distance, mb = b.distance;
    if (ma == 0 || mb == 0) return 0.0;
    final c = (dot / (ma * mb)).clamp(-1.0, 1.0);
    return math.acos(c);
    // 0 → straight, pi → U-turn
  }

  static double _polyLen(List<Offset> s) {
    double L = 0.0;
    for (int i = 1; i < s.length; i++) L += (s[i] - s[i - 1]).distance;
    return L;
  }

  // Merge pairs of near-parallel strokes that run side-by-side (double outlines)
  static List<List<Offset>> _mergeParallelStrokes(
    List<List<Offset>> strokes, {
    required double maxDist,
    required double maxAngleDiffDeg,
    required double minOverlapFrac,
  }) {
    if (strokes.length < 2) return strokes;

    final list = List<List<Offset>>.from(strokes);
    final used = List<bool>.filled(list.length, false);

    final out = <List<Offset>>[];
    final maxAngle = maxAngleDiffDeg * math.pi / 180.0;

    // Try greedy pairwise merges
    for (int i = 0; i < list.length; i++) {
      if (used[i]) continue;
      var a = list[i];
      bool mergedAny = false;

      for (int j = i + 1; j < list.length; j++) {
        if (used[j]) continue;
        final b = list[j];

        // quick bbox proximity check
        final ra = _bounds(a);
        final rb = _bounds(b);
        if (!ra.inflate(maxDist * 1.2).overlaps(rb)) continue;

        // direction similarity
        final da = a.last - a.first;
        final db = b.last - b.first;
        final ang = _angleBetween(da, db);
        if (ang > maxAngle && (math.pi - ang) > maxAngle) continue; // not parallel-ish

        // coarse alignment by endpoints (decide if b should be reversed)
        final distFF = (a.first - b.first).distance + (a.last - b.last).distance;
        final distFR = (a.first - b.last).distance + (a.last - b.first).distance;
        final bAligned = (distFR < distFF) ? b.reversed.toList() : b;

        // sample-average distance
        final (avgDist, overlapFrac) = _avgAlignedDistance(a, bAligned, samples: 32);
        if (avgDist <= maxDist && overlapFrac >= minOverlapFrac) {
          // merge into centerline by averaging pointwise (resampled to same N)
          final merged = _averageCenterline(a, bAligned, samples: 64);
          a = merged;
          used[j] = true;
          mergedAny = true;
        }
      }

      out.add(a);
      used[i] = true;
      if (mergedAny) {
        // optional: could re-run merge attempts with later strokes
      }
    }

    return out;
  }

  static Rect _bounds(List<Offset> s) {
    double minx = double.infinity, miny = double.infinity, maxx = -double.infinity, maxy = -double.infinity;
    for (final p in s) {
      if (p.dx < minx) minx = p.dx;
      if (p.dy < miny) miny = p.dy;
      if (p.dx > maxx) maxx = p.dx;
      if (p.dy > maxy) maxy = p.dy;
    }
    return Rect.fromLTRB(minx, miny, maxx, maxy);
  }

  static (double avgDist, double overlapFrac) _avgAlignedDistance(
    List<Offset> a,
    List<Offset> b, {
    int samples = 32,
  }) {
    final n = samples.clamp(4, 512);
    double sum = 0.0;
    int overlap = 0;
    for (int k = 0; k < n; k++) {
      final ta = k / (n - 1);
      final tb = ta;
      final pa = _sampleAlong(a, ta);
      final pb = _sampleAlong(b, tb);
      if (pa == null || pb == null) continue;
      sum += (pa - pb).distance;
      overlap++;
    }
    final avg = overlap > 0 ? sum / overlap : double.infinity;
    final frac = overlap / n;
    return (avg, frac);
  }

  static List<Offset> _averageCenterline(
    List<Offset> a,
    List<Offset> b, {
    int samples = 64,
  }) {
    final n = samples.clamp(4, 2048);
    final out = <Offset>[];
    for (int k = 0; k < n; k++) {
      final t = k / (n - 1);
      final pa = _sampleAlong(a, t);
      final pb = _sampleAlong(b, t);
      if (pa != null && pb != null) {
        out.add(Offset((pa.dx + pb.dx) * 0.5, (pa.dy + pb.dy) * 0.5));
      }
    }
    return out.isEmpty ? a : out;
  }

  // Sample along polyline by arc-length parameter t∈[0,1]
  static Offset? _sampleAlong(List<Offset> s, double t) {
    if (s.length < 2) return null;
    final total = _polyLen(s);
    if (total == 0) return s.first;
    final target = (t.clamp(0.0, 1.0)) * total;

    double acc = 0.0;
    for (int i = 1; i < s.length; i++) {
      final seg = (s[i] - s[i - 1]).distance;
      if (acc + seg >= target) {
        final r = (target - acc) / seg;
        return Offset(
          s[i - 1].dx + (s[i].dx - s[i - 1].dx) * r,
          s[i - 1].dy + (s[i].dy - s[i - 1].dy) * r,
        );
      }
      acc += seg;
    }
    return s.last;
  }

  // Greedy endpoint ordering to reduce pen-up travel
  static List<List<Offset>> _orderGreedy(List<List<Offset>> base) {
    if (base.isEmpty) return base;
    final remaining = List<List<Offset>>.from(base);
    final result = <List<Offset>>[];

    var current = remaining.removeAt(0);
    result.add(current);

    while (remaining.isNotEmpty) {
      final end = current.last;
      int bestIdx = 0;
      double bestDist = double.infinity;
      bool reverse = false;

      for (int i = 0; i < remaining.length; i++) {
        final r = remaining[i];
        final dStart = (r.first - end).distance;
        final dEnd = (r.last - end).distance;
        if (dStart < bestDist) { bestDist = dStart; bestIdx = i; reverse = false; }
        if (dEnd   < bestDist) { bestDist = dEnd;   bestIdx = i; reverse = true;  }
      }
      var next = remaining.removeAt(bestIdx);
      if (reverse) {
        next = next.reversed.toList();
      }
      result.add(next);
      current = next;
    }
    return result;
  }
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
  bool _externalOnly = true;
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _xCtrl.dispose(); _yCtrl.dispose(); _wCtrl.dispose();
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
