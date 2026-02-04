import 'dart:math' as math;
import 'dart:ui';
import '../models/stroke_types.dart';
import '../models/drawable_stroke.dart';
import 'stroke_timing_service.dart';

/// Service for building drawable strokes from raw vector data
class StrokeBuilderService {
  static const double targetResolution = 2000.0;
  static const double basePenWidthPx = 3.0;
  static const double boardWidth = 2000.0;
  static const double boardHeight = 2000.0;
  static const int maxDisplayPointsPerStroke = 120;

  final StrokeTimingService timingService;

  StrokeBuilderService({StrokeTimingService? timingService})
      : timingService = timingService ?? StrokeTimingService();

  /// Build drawable strokes from polylines and cubics for an object
  List<DrawableStroke> buildStrokesForObject({
    required String jsonName,
    required Offset origin,
    required double objectScale,
    required List<StrokePolyline> polylines,
    required List<StrokeCubic> cubics,
    required double srcWidth,
    required double srcHeight,
  }) {
    final strokes = <DrawableStroke>[];

    final srcMax = math.max(srcWidth, srcHeight);
    final baseUpscale = srcMax > 0 ? targetResolution / srcMax : 1.0;
    final scale = objectScale <= 0 ? 1.0 : objectScale;
    final upscale = baseUpscale * scale;

    final diag = math.sqrt(
      math.pow(srcWidth * upscale, 2) + math.pow(srcHeight * upscale, 2),
    );
    final diagSafe = diag > 1e-3 ? diag : 1.0;

    final srcBounds = _computeRawBounds(polylines, cubics);
    final srcCenter = Offset(
      srcBounds.left + srcBounds.width / 2.0,
      srcBounds.top + srcBounds.height / 2.0,
    );
    final centerScaled = Offset(
      srcCenter.dx * upscale,
      srcCenter.dy * upscale,
    );

    // Process polylines
    for (final s in polylines) {
      final pts = s.points
          .map((p) {
            final scaled = Offset(p.dx * upscale, p.dy * upscale);
            return Offset(
              scaled.dx - centerScaled.dx + origin.dx,
              scaled.dy - centerScaled.dy + origin.dy,
            );
          })
          .toList(growable: false);

      if (pts.length < 2) continue;

      strokes.add(_makeDrawableFromPoints(
        jsonName: jsonName,
        objectOrigin: origin,
        objectScale: scale,
        pts: pts,
        basePenWidth: basePenWidthPx,
        diag: diagSafe,
      ));
    }

    // Process cubics
    for (final c in cubics) {
      final ptsRaw = c.sample(upscale: upscale);
      final pts = ptsRaw
          .map((p) => Offset(
                p.dx - centerScaled.dx + origin.dx,
                p.dy - centerScaled.dy + origin.dy,
              ))
          .toList(growable: false);

      if (pts.length < 2) continue;

      strokes.add(_makeDrawableFromPoints(
        jsonName: jsonName,
        objectOrigin: origin,
        objectScale: scale,
        pts: pts,
        basePenWidth: basePenWidthPx,
        diag: diagSafe,
      ));
    }

    return strokes;
  }

  /// Build drawable strokes for text
  List<DrawableStroke> buildStrokesForText({
    required String text,
    required Offset origin,
    required double letterSize,
    required double letterGap,
    required Map<int, GlyphData> glyphCache,
    required double fontLineHeight,
    required double fontImageHeight,
  }) {
    final strokes = <DrawableStroke>[];
    final scale = letterSize / fontLineHeight;
    final diagBoard = math.sqrt(boardWidth * boardWidth + boardHeight * boardHeight);

    double cursorX = origin.dx;
    final double baselineWorldY = origin.dy;
    final double baselineGlyph = fontImageHeight / 2.0;
    final double baselineGlyphScaled = baselineGlyph * scale;

    const double spaceWidthFactor = 0.5;

    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      final code = ch.codeUnitAt(0);

      if (ch == ' ') {
        cursorX += letterSize * spaceWidthFactor;
        continue;
      }

      final glyph = glyphCache[code];
      if (glyph == null) {
        cursorX += letterSize * spaceWidthFactor;
        continue;
      }

      final gb = glyph.bounds;
      final glyphWidth = math.max(gb.width, 1e-3);
      final glyphLeft = gb.left;

      final double letterOffsetX = cursorX - glyphLeft * scale;
      final double letterOffsetY = baselineWorldY - baselineGlyphScaled;

      for (final stroke in glyph.cubics) {
        final ptsRaw = stroke.sample(upscale: scale);
        if (ptsRaw.length < 2) continue;

        final ptsPlaced = ptsRaw
            .map((p) => Offset(
                  p.dx + letterOffsetX,
                  p.dy + letterOffsetY,
                ))
            .toList(growable: false);

        strokes.add(_makeDrawableFromPoints(
          jsonName: text,
          objectOrigin: origin,
          objectScale: scale,
          pts: ptsPlaced,
          basePenWidth: basePenWidthPx,
          diag: diagBoard,
        ));
      }

      final glyphWidthScaled = glyphWidth * scale;
      cursorX += glyphWidthScaled + letterGap;
    }

    return strokes;
  }

  DrawableStroke _makeDrawableFromPoints({
    required String jsonName,
    required Offset objectOrigin,
    required double objectScale,
    required List<Offset> pts,
    required double basePenWidth,
    required double diag,
  }) {
    final scale = objectScale <= 0 ? 1.0 : objectScale;
    final clampedScale = scale.clamp(0.1, 3.0);
    double scaleFactor = clampedScale <= 1.0
        ? clampedScale
        : 1.0 + 0.4 * (clampedScale - 1.0);

    int effectiveMax = (maxDisplayPointsPerStroke * scaleFactor).round();
    if (effectiveMax < 8) effectiveMax = 8;
    if (effectiveMax > maxDisplayPointsPerStroke) {
      effectiveMax = maxDisplayPointsPerStroke;
    }

    final workPts = _downsamplePolyline(pts, effectiveMax);
    final n = workPts.length;

    final cumGeom = List<double>.filled(n, 0.0);
    final cumCost = List<double>.filled(n, 0.0);

    double length = 0.0;
    double cost = 0.0;
    double prevSharpNorm = 0.0;
    final double angleScale = timingService.config.curvatureAngleScale.abs() < 1e-3
        ? 1.0
        : timingService.config.curvatureAngleScale;

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
          final clamped = dot.clamp(-1.0, 1.0);
          angDeg = math.acos(clamped) * 180.0 / math.pi;
        }
      }

      double sharpNorm = (angDeg / angleScale).clamp(0.0, 1.5);
      final smoothedSharp = 0.7 * prevSharpNorm + 0.3 * sharpNorm;
      prevSharpNorm = smoothedSharp;

      final slowFactor = 1.0 + timingService.config.curvatureProfileFactor * smoothedSharp;
      final segCost = segLen * slowFactor;

      cost += segCost;
      cumGeom[i] = length;
      cumCost[i] = cost;
    }

    if (length < 0.0) length = 0.0;

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
    final curvature = StrokeTimingService.estimateCurvatureDeg(workPts);
    final bounds = _boundsOfPoints(workPts);

    // Apply wobble for hand-drawn effect
    double amp = 0.0;
    if (length > 0.02 * diag) {
      final lenNorm = (length / diag).clamp(0.0, 1.0);
      final curvNorm = (curvature / 70.0).clamp(0.0, 1.0);
      final baseAmp = basePenWidth * 0.9;
      amp = baseAmp *
          (0.5 + 0.8 * math.pow(lenNorm, 0.7)) *
          (0.6 + 0.4 * (1.0 - curvNorm));
      amp = amp.clamp(0.5, basePenWidth * 2.0);
    }

    final displayPts = amp > 0.0 ? _applyWobble(workPts, amp) : workPts;

    // Compute initial draw time
    final lengthK = length / 1000.0;
    final curvNormGlobal = (curvature / 70.0).clamp(0.0, 1.0);
    final rawTime = timingService.config.minStrokeTimeSec +
        lengthK * timingService.config.lengthTimePerKPxSec +
        curvNormGlobal * timingService.config.curvatureExtraMaxSec;
    final drawTimeSec = rawTime.clamp(
      timingService.config.minStrokeTimeSec,
      timingService.config.maxStrokeTimeSec,
    );

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
    );
  }

  Rect _computeRawBounds(List<StrokePolyline> polys, List<StrokeCubic> cubics) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;

    for (final s in polys) {
      for (final p in s.points) {
        if (p.dx < minX) minX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy > maxY) maxY = p.dy;
      }
    }

    for (final s in cubics) {
      for (final seg in s.segments) {
        for (final p in [seg.p0, seg.c1, seg.c2, seg.p1]) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
      }
    }

    if (minX == double.infinity) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    final w = math.max(1e-3, maxX - minX);
    final h = math.max(1e-3, maxY - minY);
    return Rect.fromLTWH(minX, minY, w, h);
  }

  List<Offset> _downsamplePolyline(List<Offset> pts, int maxPoints) {
    final n = pts.length;
    if (n <= maxPoints || maxPoints <= 2) return pts;

    double totalLen = 0.0;
    final segLen = List<double>.filled(n, 0.0);

    for (int i = 1; i < n; i++) {
      final d = (pts[i] - pts[i - 1]).distance;
      segLen[i] = d;
      totalLen += d;
    }

    if (totalLen <= 1e-6) {
      return <Offset>[pts.first, pts.last];
    }

    final out = <Offset>[];
    out.add(pts.first);

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
        final p = Offset(
          pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) * t,
          pts[i - 1].dy + (pts[i].dy - pts[i - 1].dy) * t,
        );
        out.add(p);
        nextTarget += step;
      } else {
        accum += d;
        i++;
      }
    }

    out.add(pts.last);
    return out;
  }

  Offset _centroid(List<Offset> pts) {
    if (pts.isEmpty) return Offset.zero;
    double sx = 0.0, sy = 0.0;
    for (final p in pts) {
      sx += p.dx;
      sy += p.dy;
    }
    final n = pts.length.toDouble();
    return Offset(sx / n, sy / n);
  }

  List<Offset> _applyWobble(List<Offset> pts, double amp) {
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
      final combined = 0.6 * waveFast + 0.4 * waveSlow;

      final w = combined * amp * fade;

      out.add(Offset(pts[i].dx + nx * w, pts[i].dy + ny * w));
    }
    return out;
  }

  Rect _boundsOfPoints(List<Offset> pts) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (minX == double.infinity) {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
