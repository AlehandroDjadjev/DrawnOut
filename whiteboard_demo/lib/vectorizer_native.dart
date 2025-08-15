import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Path, Rect;

import 'package:opencv_dart/opencv_dart.dart' as cv;

class Vectorizer {
  static Future<List<List<Offset>>> vectorize({
    required List<int> bytes,
    double worldScale = 1.0,
    String edgeMode = 'Canny',
    int blurK = 5,
    double cannyLo = 50,
    double cannyHi = 160,
    double dogSigma = 1.2,
    double dogK = 1.6,
    double dogThresh = 6.0,
    double epsilon = 1.1187500000000001,
    double resampleSpacing = 1.410714285714286,
    double minPerimeter = 19.839285714285793,
    bool retrExternalOnly = true,
    double angleThresholdDeg = 30,
    int angleWindow = 4,
    int smoothPasses = 3,
    bool mergeParallel = true,
    double mergeMaxDist = 12.0,
    double minStrokeLen = 8.70,
    int minStrokePoints = 6,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('No image bytes provided.');
    }

    final u8 = bytes is Uint8List ? bytes as Uint8List : Uint8List.fromList(bytes);

    final src = cv.imdecode(u8, cv.IMREAD_COLOR);
    if (src.cols == 0 || src.rows == 0) {
      src.dispose();
      throw StateError(
        'Failed to decode image (unsupported/empty data). '
        'Try PNG or JPEG (avoid HEIC/WEBP on Windows).',
      );
    }

    final gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    final oddBlurK = (blurK.isOdd ? blurK : blurK + 1).clamp(3, 99);
    final blur = cv.gaussianBlur(gray, (oddBlurK, oddBlurK), 0);

    cv.Mat edge;
    if (edgeMode == 'DoG') {
      final g1 = cv.gaussianBlur(gray, (0, 0), dogSigma);
      final g2 = cv.gaussianBlur(gray, (0, 0), dogSigma * dogK);
      final diff = cv.subtract(g1, g2);
      final absd = cv.convertScaleAbs(diff);
      final (_, th) = cv.threshold(absd, dogThresh, 255, cv.THRESH_BINARY);
      edge = th;
      g1.dispose(); g2.dispose(); diff.dispose(); absd.dispose();
    } else {
      edge = cv.canny(blur, cannyLo, cannyHi);
    }

    final mode = retrExternalOnly ? cv.RETR_EXTERNAL : cv.RETR_LIST;
    final (contours, _) = cv.findContours(edge, mode, cv.CHAIN_APPROX_NONE);

    final imgW = src.cols, imgH = src.rows;
    final cx = imgW / 2.0, cy = imgH / 2.0;

    final rawStrokes = <List<Offset>>[];
    for (final cnt in contours) {
      final peri = cv.arcLength(cnt, false);
      if (peri < minPerimeter) continue;

      final approx = cv.approxPolyDP(cnt, epsilon, false);
      final polyImg = _resampleCv(approx, spacing: resampleSpacing);
      if (polyImg.length < 2) continue;

      var polyWorld = polyImg
          .map((p) => Offset((p.dx - cx) * worldScale, (p.dy - cy) * worldScale))
          .toList();

      if (smoothPasses > 0) {
        polyWorld = _smoothPolyline(polyWorld, passes: smoothPasses);
      }

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

    final merged = mergeParallel
        ? _mergeParallelStrokes(rawStrokes,
            maxDist: mergeMaxDist,
            maxAngleDiffDeg: 12.0,
            minOverlapFrac: 0.45)
        : rawStrokes;

    merged.sort((a, b) {
      final minAx = a.map((p) => p.dx).reduce(math.min);
      final minBx = b.map((p) => p.dx).reduce(math.min);
      if (minAx != minBx) return minAx.compareTo(minBx);
      final lenA = _polyLen(a), lenB = _polyLen(b);
      return lenB.compareTo(lenA);
    });
    final ordered = _orderGreedy(merged);

    src.dispose(); gray.dispose(); blur.dispose(); edge.dispose();

    return ordered;
  }

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
        if (cur.length >= 2) segs.add(cur);
        cur = [pts[i]];
        curLen = 0.0;
      }
    }
    cur.add(pts.last);
    if (cur.length >= 2) segs.add(cur);

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
  }

  static double _polyLen(List<Offset> s) {
    double L = 0.0;
    for (int i = 1; i < s.length; i++) L += (s[i] - s[i - 1]).distance;
    return L;
  }

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

    for (int i = 0; i < list.length; i++) {
      if (used[i]) continue;
      var a = list[i];
      bool mergedAny = false;

      for (int j = i + 1; j < list.length; j++) {
        if (used[j]) continue;
        final b = list[j];

        final ra = _bounds(a);
        final rb = _bounds(b);
        if (!ra.inflate(maxDist * 1.2).overlaps(rb)) continue;

        final da = a.last - a.first;
        final db = b.last - b.first;
        final ang = _angleBetween(da, db);
        if (ang > maxAngle && (math.pi - ang) > maxAngle) continue;

        final distFF = (a.first - b.first).distance + (a.last - b.last).distance;
        final distFR = (a.first - b.last).distance + (a.last - b.first).distance;
        final bAligned = (distFR < distFF) ? b.reversed.toList() : b;

        final (avgDist, overlapFrac) = _avgAlignedDistance(a, bAligned, samples: 32);
        if (avgDist <= maxDist && overlapFrac >= minOverlapFrac) {
          final merged = _averageCenterline(a, bAligned, samples: 64);
          a = merged;
          used[j] = true;
          mergedAny = true;
        }
      }

      out.add(a);
      used[i] = true;
      if (mergedAny) {
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



