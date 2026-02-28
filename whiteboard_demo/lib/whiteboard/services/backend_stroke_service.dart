import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../models/drawable_stroke.dart';
import '../../vector_stroke_decoder.dart';

// ── Raw data types ──────────────────────────────────────────────────────────

/// One cubic Bézier segment: p0 → (c1, c2) → p1.
class CubicSegment {
  final Offset p0, c1, c2, p1;
  const CubicSegment(
      {required this.p0,
      required this.c1,
      required this.c2,
      required this.p1});
}

/// A single stroke from the backend pipeline (list of cubic segments + color).
class RawCubicStroke {
  final List<CubicSegment> segments;
  final Color color;
  const RawCubicStroke(this.segments, {this.color = Colors.black});
}

// ── Color mapping (mirrors Python COLOR_ORDER_LIGHT_TO_DARK in ImagePipeline) ──

const _colorGroupMap = <int, Color>{
  1: Color(0xFFFFFFFF), // white
  2: Color(0xFFFFFF00), // yellow
  3: Color(0xFFFF8C00), // orange
  4: Color(0xFF00CED1), // cyan
  5: Color(0xFF228B22), // green
  6: Color(0xFFFF00FF), // magenta
  7: Color(0xFFDC143C), // red
  8: Color(0xFF1E90FF), // blue
  9: Color(0xFF6A0DAD), // purple
  10: Color(0xFF808080), // gray
  11: Color(0xFF000000), // black
};

Color _colorForGroupId(int id) => _colorGroupMap[id] ?? Colors.black;

// ── BackendStrokeService ────────────────────────────────────────────────────

/// Parses cubic Bézier stroke JSON produced by the backend image pipeline and
/// builds [DrawableStroke] objects (or plain polylines) ready for rendering.
///
/// Ported directly from [DrawnOutWhiteboard/visual_whiteboard/lib/main.dart].
class BackendStrokeService {
  // ─── Timing constants (match DrawnOutWhiteboard defaults) ────────────────
  static const double _minStrokeTimeSec = 0.29;
  static const double _maxStrokeTimeSec = 0.8;
  static const double _lengthTimePerKPxSec = 0.3;
  static const double _curvatureExtraMaxSec = 0.08;
  static const double _curvatureProfileFactor = 1.5;
  static const double _curvatureAngleScale = 80.0;
  static const double _baseTravelTimeSec = 0.15;
  static const double _travelTimePerKPxSec = 0.12;
  static const double _minTravelTimeSec = 0.15;
  static const double _maxTravelTimeSec = 0.35;
  static const double _basePenWidthPx = 4.0;
  static const double _targetResolution = 2000.0;
  static const int _maxDisplayPointsPerStroke = 120;
  static const int _stepsPerCubicSegment = 18;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Parse a backend stroke JSON map into raw cubic strokes + source dimensions.
  ///
  /// Returns null if the JSON is invalid or has no strokes.
  static ({
    List<RawCubicStroke> strokes,
    double srcWidth,
    double srcHeight,
  })? parseJson(Map<String, dynamic> json) {
    final strokesRaw = json['strokes'];
    if (strokesRaw is! List || strokesRaw.isEmpty) return null;

    final srcWidth = (json['width'] as num?)?.toDouble() ?? 1000.0;
    final srcHeight = (json['height'] as num?)?.toDouble() ?? 1000.0;
    final format =
        (json['vector_format'] as String?)?.toLowerCase() ?? 'bezier_cubic';

    if (format != 'bezier_cubic') {
      // Polyline format from older pipelines — degrade gracefully
      return _parsePolylineJson(strokesRaw, srcWidth, srcHeight);
    }

    debugPrint('🔍 DECODE │ BackendStrokeService.parseJson (backend_stroke_service.dart) bezier_cubic format');
    final result = <RawCubicStroke>[];
    for (var idx = 0; idx < strokesRaw.length; idx++) {
      final s = strokesRaw[idx];
      if (s is! Map) continue;
      final segsRaw = s['segments'];
      if (idx == 0) debugPrint('🔍 DECODE │   first stroke segments type: ${segsRaw.runtimeType}');
      final segsDecoded = VectorStrokeDecoder.decodeSegments(segsRaw);
      if (idx == 0) debugPrint('🔍 DECODE │   first stroke decoded: ${segsDecoded.length} segments');

      final colorGroupId = (s['color_group_id'] as num?)?.toInt() ?? 11;
      final color = _colorForGroupId(colorGroupId);

      final segs = <CubicSegment>[];
      for (final seg in segsDecoded) {
        if (seg.length >= 8) {
          segs.add(CubicSegment(
            p0: Offset(seg[0], seg[1]),
            c1: Offset(seg[2], seg[3]),
            c2: Offset(seg[4], seg[5]),
            p1: Offset(seg[6], seg[7]),
          ));
        }
      }
      if (segs.isNotEmpty) result.add(RawCubicStroke(segs, color: color));
    }

    if (result.isEmpty) return null;
    return (strokes: result, srcWidth: srcWidth, srcHeight: srcHeight);
  }

  /// Convert backend cubic strokes to plain polylines in world/layout space.
  ///
  /// Use this when you want to add the image strokes to a [StrokePlan] that
  /// drives the existing [SketchPlayer] animation system.
  ///
  /// [worldCenter]  – center of the image in world (canvas-centered) space.
  /// [targetWidth]  – desired image width in world pixels.
  /// [srcWidth]/[srcHeight] – original image dimensions from the JSON.
  static List<List<Offset>> toPolylines({
    required List<RawCubicStroke> strokes,
    required double srcWidth,
    required double srcHeight,
    required Offset worldCenter,
    required double targetWidth,
  }) {
    if (strokes.isEmpty) return const [];
    final effScale = targetWidth / math.max(1.0, srcWidth);
    final topLeft = Offset(
      worldCenter.dx - targetWidth / 2.0,
      worldCenter.dy - (srcHeight * effScale) / 2.0,
    );

    final result = <List<Offset>>[];
    for (final stroke in strokes) {
      final pts = _sampleCubicStroke(stroke, upscale: effScale);
      if (pts.length < 2) continue;
      final placed = pts.map((p) => p + topLeft).toList();
      result.add(placed);
    }
    return result;
  }

  /// Build [DrawableStroke] from backend text strokes (in_world_space: true).
  ///
  /// Strokes are already in world coordinates — no centering/scale transform.
  /// Same pipeline as visual_whiteboard's _addTextStrokesFromBackend.
  static List<DrawableStroke> buildDrawableStrokesFromWorldSpace({
    required List<RawCubicStroke> strokes,
    required Offset origin,
    String label = 'text',
  }) {
    if (strokes.isEmpty) return const [];

    const upscale = 1.0;
    final diag = math.sqrt(
      math.pow(_targetResolution, 2) + math.pow(_targetResolution, 2),
    );
    final result = <DrawableStroke>[];

    for (final s in strokes) {
      final ptsRaw = _sampleCubicStroke(s, upscale: upscale);
      if (ptsRaw.length < 2) continue;
      result.add(_makeDrawableFromPoints(
        jsonName: label,
        objectOrigin: origin,
        objectScale: 1.0,
        pts: ptsRaw,
        diag: diag,
        strokeColor: s.color,
      ));
    }

    _assignTravelTimes(result);
    return result;
  }

  /// Build [DrawableStroke] objects from backend cubic strokes.
  ///
  /// The resulting list is ready for [WhiteboardPainter] — it includes
  /// wobble, timing, and curvature-based draw-cost data.
  ///
  /// [label]        – name used for grouping / erase.
  /// [origin]       – world-space center of the image (for placement).
  /// [objectScale]  – additional scale multiplier (1.0 = default).
  static List<DrawableStroke> buildDrawableStrokes({
    required List<RawCubicStroke> strokes,
    required double srcWidth,
    required double srcHeight,
    required Offset origin,
    double objectScale = 1.0,
    String label = 'backend_image',
  }) {
    if (strokes.isEmpty) return const [];

    final srcMax = math.max(srcWidth, srcHeight);
    final baseUpscale = srcMax > 0 ? _targetResolution / srcMax : 1.0;
    final scale = objectScale <= 0 ? 1.0 : objectScale;
    final upscale = baseUpscale * scale;

    // Compute source-space center from stroke bounds (mirrors DrawnOutWhiteboard)
    final srcBounds = _computeRawBounds(strokes);
    final srcCenter = Offset(
      srcBounds.left + srcBounds.width / 2.0,
      srcBounds.top + srcBounds.height / 2.0,
    );
    final centerScaled = srcCenter * upscale;

    final diag = math.sqrt(
      math.pow(srcWidth * upscale, 2) + math.pow(srcHeight * upscale, 2),
    );
    final diagSafe = diag > 1e-3 ? diag : 1.0;

    final result = <DrawableStroke>[];
    for (final s in strokes) {
      final ptsRaw = _sampleCubicStroke(s, upscale: upscale);
      final pts = ptsRaw
          .map((p) => Offset(
                p.dx - centerScaled.dx + origin.dx,
                p.dy - centerScaled.dy + origin.dy,
              ))
          .toList(growable: false);

      if (pts.length < 2) continue;
      result.add(_makeDrawableFromPoints(
        jsonName: label,
        objectOrigin: origin,
        objectScale: scale,
        pts: pts,
        diag: diagSafe,
        strokeColor: s.color,
      ));
    }

    _assignTravelTimes(result);
    return result;
  }

  // ── Sampling ───────────────────────────────────────────────────────────────

  static List<Offset> _sampleCubicStroke(RawCubicStroke s,
      {required double upscale}) {
    final pts = <Offset>[];
    bool first = true;
    for (final seg in s.segments) {
      for (int i = 0; i <= _stepsPerCubicSegment; i++) {
        final t = i / _stepsPerCubicSegment;
        final p = _evalCubic(seg, t);
        final q = p * upscale;
        if (!first && (q - pts.last).distance < 0.05) continue;
        pts.add(q);
        first = false;
      }
    }
    return pts;
  }

  static Offset _evalCubic(CubicSegment seg, double t) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    return Offset(
      mt2 * mt * seg.p0.dx +
          3 * mt2 * t * seg.c1.dx +
          3 * mt * t2 * seg.c2.dx +
          t2 * t * seg.p1.dx,
      mt2 * mt * seg.p0.dy +
          3 * mt2 * t * seg.c1.dy +
          3 * mt * t2 * seg.c2.dy +
          t2 * t * seg.p1.dy,
    );
  }

  // ── DrawableStroke builder (mirrors _makeDrawableFromPoints) ───────────────

  static DrawableStroke _makeDrawableFromPoints({
    required String jsonName,
    required Offset objectOrigin,
    required double objectScale,
    required List<Offset> pts,
    required double diag,
    Color strokeColor = Colors.black,
  }) {
    final scale = objectScale <= 0 ? 1.0 : objectScale;
    final clampedScale = scale.clamp(0.1, 3.0);
    final scaleFactor = clampedScale <= 1.0
        ? clampedScale
        : 1.0 + 0.4 * (clampedScale - 1.0);

    int effectiveMax =
        (_maxDisplayPointsPerStroke * scaleFactor).round().clamp(8, _maxDisplayPointsPerStroke);
    final workPts = _downsamplePolyline(pts, effectiveMax);
    final n = workPts.length;

    final cumGeom = List<double>.filled(n, 0.0);
    final cumCost = List<double>.filled(n, 0.0);

    double length = 0.0;
    double cost = 0.0;
    double prevSharpNorm = 0.0;

    for (int i = 1; i < n; i++) {
      final v = workPts[i] - workPts[i - 1];
      final segLen = v.distance;
      if (segLen < 1e-6) {
        cumGeom[i] = length;
        cumCost[i] = cost;
        continue;
      }
      length += segLen;

      double angDeg = 0.0;
      if (i > 1) {
        final vPrev = workPts[i - 1] - workPts[i - 2];
        final lenPrev = vPrev.distance;
        if (lenPrev >= 1e-6) {
          final dot = (vPrev.dx * v.dx + vPrev.dy * v.dy) / (lenPrev * segLen);
          angDeg = math.acos(dot.clamp(-1.0, 1.0)) * 180.0 / math.pi;
        }
      }

      final sharpNorm = (angDeg / _curvatureAngleScale).clamp(0.0, 1.5);
      final smoothedSharp = 0.7 * prevSharpNorm + 0.3 * sharpNorm;
      prevSharpNorm = smoothedSharp;

      cost += segLen * (1.0 + _curvatureProfileFactor * smoothedSharp);
      cumGeom[i] = length;
      cumCost[i] = cost;
    }

    double drawCostTotal;
    if (cost <= 0.0) {
      if (n > 1) {
        for (int i = 1; i < n; i++) {
          final t = i / (n - 1);
          cumGeom[i] = length * t;
          cumCost[i] = t;
        }
      }
      drawCostTotal = 1.0;
    } else {
      drawCostTotal = cost;
    }

    final centroid = _centroid(workPts);
    final curvature = _estimateCurvatureDeg(workPts);
    final bounds = _boundsOfPoints(workPts);

    // Wobble amplitude (same formula as DrawnOutWhiteboard)
    double amp = 0.0;
    if (length > 0.02 * diag) {
      final lenNorm = (length / diag).clamp(0.0, 1.0);
      final curvNorm = (curvature / 70.0).clamp(0.0, 1.0);
      final baseAmp = _basePenWidthPx * 0.9;
      amp = baseAmp *
          (0.5 + 0.8 * math.pow(lenNorm, 0.7)) *
          (0.6 + 0.4 * (1.0 - curvNorm));
      amp = amp.clamp(0.5, _basePenWidthPx * 2.0);
    }

    final displayPts = amp > 0.0 ? _applyWobble(workPts, amp) : workPts;

    final lengthK = length / 1000.0;
    final curvNormGlobal = (curvature / 70.0).clamp(0.0, 1.0);
    final drawTimeSec = (_minStrokeTimeSec +
            lengthK * _lengthTimePerKPxSec +
            curvNormGlobal * _curvatureExtraMaxSec)
        .clamp(_minStrokeTimeSec, _maxStrokeTimeSec)
        .toDouble();

    return DrawableStroke(
      jsonName: jsonName,
      objectOrigin: objectOrigin,
      objectScale: objectScale,
      points: displayPts,
      originalPoints: workPts,
      lengthPx: length,
      centroid: centroid,
      bounds: bounds,
      curvatureMetricDeg: curvature,
      cumGeomLen: cumGeom,
      cumDrawCost: cumCost,
      drawCostTotal: drawCostTotal,
      drawTimeSec: drawTimeSec,
      color: strokeColor,
    );
  }

  // ── Travel-time assignment between consecutive strokes ─────────────────────

  static void _assignTravelTimes(List<DrawableStroke> strokes) {
    DrawableStroke? prev;
    for (final s in strokes) {
      double travel = 0.0;
      if (prev != null) {
        final dist = (s.points.first - prev.points.last).distance;
        final distK = dist / 1000.0;
        travel = (_baseTravelTimeSec + distK * _travelTimePerKPxSec)
            .clamp(_minTravelTimeSec, _maxTravelTimeSec)
            .toDouble();
      }
      s.travelTimeBeforeSec = travel;
      s.timeWeight = travel + s.drawTimeSec;
      prev = s;
    }
  }

  // ── Geometry helpers ────────────────────────────────────────────────────────

  static Rect _computeRawBounds(List<RawCubicStroke> strokes) {
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final s in strokes) {
      for (final seg in s.segments) {
        for (final p in [seg.p0, seg.c1, seg.c2, seg.p1]) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
      }
    }
    if (minX == double.infinity) return const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTWH(minX, minY, math.max(1e-3, maxX - minX),
        math.max(1e-3, maxY - minY));
  }

  static List<Offset> _downsamplePolyline(List<Offset> pts, int maxPoints) {
    final n = pts.length;
    if (n <= maxPoints || maxPoints <= 2) return pts;

    double totalLen = 0.0;
    final segLen = List<double>.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      final d = (pts[i] - pts[i - 1]).distance;
      segLen[i] = d;
      totalLen += d;
    }
    if (totalLen <= 1e-6) return [pts.first, pts.last];

    final out = <Offset>[pts.first];
    final step = totalLen / (maxPoints - 1);
    double accum = 0.0;
    double nextTarget = step;
    int i = 1;

    while (i < n - 1 && out.length < maxPoints - 1) {
      final d = segLen[i];
      if (d <= 0.0) {
        i++;
        continue;
      }
      if (accum + d >= nextTarget) {
        final t = (nextTarget - accum) / d;
        out.add(Offset(
          pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) * t,
          pts[i - 1].dy + (pts[i].dy - pts[i - 1].dy) * t,
        ));
        nextTarget += step;
      } else {
        accum += d;
        i++;
      }
    }
    out.add(pts.last);
    return out;
  }

  static Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    return Offset(sx / pts.length, sy / pts.length);
  }

  static double _estimateCurvatureDeg(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double sumAng = 0.0;
    int cnt = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final v1 = pts[i] - pts[i - 1];
      final v2 = pts[i + 1] - pts[i];
      final l1 = v1.distance, l2 = v2.distance;
      if (l1 < 1e-3 || l2 < 1e-3) continue;
      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (l1 * l2);
      sumAng += math.acos(dot.clamp(-1.0, 1.0)) * 180.0 / math.pi;
      cnt++;
    }
    return cnt == 0 ? 0.0 : sumAng / cnt;
  }

  static Rect _boundsOfPoints(List<Offset> pts) {
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (minX == double.infinity) return const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<Offset> _applyWobble(List<Offset> pts, double amp) {
    final n = pts.length;
    if (n < 3) return pts;
    final out = <Offset>[];
    for (int i = 0; i < n; i++) {
      final pPrev = pts[i == 0 ? 0 : i - 1];
      final pNext = pts[i == n - 1 ? n - 1 : i + 1];
      final dir = pNext - pPrev;
      final len = dir.distance;
      if (len < 1e-6) {
        out.add(pts[i]);
        continue;
      }
      final nx = -dir.dy / len;
      final ny = dir.dx / len;
      final t = i / (n - 1);
      final fade = math.sin(t * math.pi);
      final waveFast = math.sin(t * 5.0 * math.pi);
      final waveSlow = math.sin(t * 2.0 * math.pi);
      final w = (0.6 * waveFast + 0.4 * waveSlow) * amp * fade;
      out.add(Offset(pts[i].dx + nx * w, pts[i].dy + ny * w));
    }
    return out;
  }

  // ── Polyline fallback for older pipeline format ───────────────────────────

  static ({
    List<RawCubicStroke> strokes,
    double srcWidth,
    double srcHeight,
  }) _parsePolylineJson(
      List strokesRaw, double srcWidth, double srcHeight) {
    // Convert polyline strokes into degenerate cubic (straight-line) strokes.
    // Supports both List [[x,y],...] and base64 Float32 packed arrays.
    debugPrint('🔍 DECODE │ BackendStrokeService._parsePolylineJson (backend_stroke_service.dart) polyline format');
    final result = <RawCubicStroke>[];
    for (var idx = 0; idx < strokesRaw.length; idx++) {
      final s = strokesRaw[idx];
      if (s is! Map) continue;
      final ptsRaw = s['points'];
      if (idx == 0) debugPrint('🔍 DECODE │   first stroke points type: ${ptsRaw.runtimeType}');
      final pts = VectorStrokeDecoder.decodePoints(ptsRaw);
      if (idx == 0) debugPrint('🔍 DECODE │   first stroke decoded: ${pts.length} points');
      if (pts.length < 2) continue;
      final colorGroupId = (s['color_group_id'] as num?)?.toInt() ?? 11;
      final color = _colorForGroupId(colorGroupId);
      final segs = <CubicSegment>[];
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        segs.add(CubicSegment(p0: a, c1: a, c2: b, p1: b));
      }
      if (segs.isNotEmpty) result.add(RawCubicStroke(segs, color: color));
    }
    return (strokes: result, srcWidth: srcWidth, srcHeight: srcHeight);
  }
}
