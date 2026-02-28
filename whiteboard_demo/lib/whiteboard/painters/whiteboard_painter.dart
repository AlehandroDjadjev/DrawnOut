import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/drawable_stroke.dart';

/// Immutable board-to-screen transform used by whiteboard layers.
class WhiteboardViewportTransform {
  final double scale;
  final double translateX;
  final double translateY;

  const WhiteboardViewportTransform({
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  /// Convert a world point (whiteboard coordinates) to screen space.
  Offset worldToScreen(Offset world) {
    return Offset(
      world.dx * scale + translateX,
      world.dy * scale + translateY,
    );
  }
}

/// Custom painter for rendering whiteboard strokes with animation.
///
/// Supports per-stroke colors from [DrawableStroke.color], a physics-based
/// speed warp within each stroke (accel → peak → decel), and curvature-aware
/// draw-cost timing — ported directly from DrawnOutWhiteboard.
class WhiteboardPainter extends CustomPainter {
  final List<DrawableStroke> staticStrokes;
  final List<DrawableStroke> animStrokes;
  final double animationT;
  final double basePenWidth;
  final bool stepMode;
  final int stepStrokeCount;
  final double boardWidth;
  final double boardHeight;

  /// Fallback stroke color used when [DrawableStroke.color] equals Colors.black
  /// and [useStrokeColors] is false.
  final Color strokeColor;

  /// When true the per-stroke [DrawableStroke.color] is used instead of
  /// the global [strokeColor].  Set to true for backend-pipeline images.
  final bool useStrokeColors;

  // ── Within-stroke speed envelope (ported from DrawnOutWhiteboard) ──────────
  final double speedStartPct;
  final double speedEndPct;
  final double speedPeakMult;
  final double speedPeakTime;

  const WhiteboardPainter({
    required this.staticStrokes,
    required this.animStrokes,
    required this.animationT,
    required this.basePenWidth,
    required this.stepMode,
    required this.stepStrokeCount,
    required this.boardWidth,
    required this.boardHeight,
    this.strokeColor = Colors.black,
    this.useStrokeColors = false,
    this.speedStartPct = 0.08,
    this.speedEndPct = 0.25,
    this.speedPeakMult = 2.50,
    this.speedPeakTime = 0.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (staticStrokes.isEmpty && animStrokes.isEmpty) return;

    final viewport = computeViewportTransform(
      size,
      boardWidth: boardWidth,
      boardHeight: boardHeight,
      padding: 80,
    );
    final scale = viewport.scale;

    canvas.save();
    canvas.translate(viewport.translateX, viewport.translateY);
    canvas.scale(scale);

    final allStrokes = <DrawableStroke>[...staticStrokes, ...animStrokes];

    if (stepMode) {
      final count = stepStrokeCount.clamp(0, allStrokes.length);
      for (int i = 0; i < count; i++) {
        _drawStroke(canvas, allStrokes[i], 1.0, scale);
      }
    } else {
      for (final s in staticStrokes) {
        _drawStroke(canvas, s, 1.0, scale);
      }

      if (animStrokes.isNotEmpty) {
        final totalWeight =
            animStrokes.fold<double>(0.0, (s, d) => s + d.timeWeight);
        final clampedT = animationT.clamp(0.0, 1.0);
        final target = totalWeight > 0 ? totalWeight * clampedT : 0.0;

        double acc = 0.0;
        for (final stroke in animStrokes) {
          final travel = stroke.travelTimeBeforeSec;
          final draw = stroke.drawTimeSec;
          if (draw <= 0.0 && travel <= 0.0) continue;

          final strokeStart = acc;
          final travelEnd = strokeStart + travel;
          final strokeEnd = travelEnd + draw;
          acc = strokeEnd;

          if (target >= strokeEnd) {
            _drawStroke(canvas, stroke, 1.0, scale);
            continue;
          }

          if (target <= strokeStart) break;
          if (target < travelEnd) break;

          final local = (target - travelEnd) / draw;
          final phase = local.clamp(0.0, 1.0);
          if (phase > 0.0) _drawStroke(canvas, stroke, phase, scale);
          break;
        }
      }
    }

    canvas.restore();
  }

  void _drawStroke(
      Canvas canvas, DrawableStroke stroke, double phase, double viewScale) {
    final pts = stroke.points;
    if (pts.length < 2) return;

    const double drawFrac = 0.8;
    final local = phase.clamp(0.0, 1.0);
    if (local <= 0.0) return;

    final drawPhase = (local >= drawFrac) ? 1.0 : local / drawFrac;
    if (drawPhase <= 0.0) return;

    final n = pts.length;
    final totalCost = stroke.drawCostTotal;

    int idxMax;
    if (drawPhase >= 1.0 || totalCost <= 0.0) {
      idxMax = n - 1;
    } else {
      final warped = _warpStrokePhase(drawPhase);
      final targetCost = warped * totalCost;
      idxMax = _findIndexForCost(stroke.cumDrawCost, targetCost);
      if (idxMax < 1) idxMax = 1;
      if (idxMax >= n) idxMax = n - 1;
    }

    if (idxMax < 1) return;

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 1; i <= idxMax; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }

    final penW = (basePenWidth / viewScale).clamp(0.5, 10.0);
    final color = useStrokeColors ? stroke.color : strokeColor;

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = penW,
    );
  }

  // ── Speed warp: maps linear t → warped progress (accel→peak→decel) ─────────
  // Ported verbatim from DrawnOutWhiteboard's _warpStrokePhase.
  double _warpStrokePhase(double t) {
    t = t.clamp(0.0, 1.0);

    double start = speedStartPct.clamp(0.0, 0.49);
    double end = speedEndPct.clamp(0.0, 0.49);

    final t1 = start;
    final t3 = (1.0 - end);

    if (t3 <= t1 + 1e-4) return t;

    double t2 = speedPeakTime.clamp(0.0, 1.0);
    t2 = t2.clamp(t1 + 1e-4, t3 - 1e-4);

    final peak = speedPeakMult.clamp(1.0, 10.0);

    double segFull(double vA, double vB, double L) {
      if (L <= 0.0) return 0.0;
      return L * (vA + vB) * 0.5;
    }

    double smoothInt(double x) {
      final x2 = x * x;
      final x4 = x2 * x2;
      final x5 = x4 * x;
      final x6 = x5 * x;
      return (x6 - 3.0 * x5 + 2.5 * x4);
    }

    double segPartial(double vA, double vB, double L, double x) {
      if (L <= 0.0) return 0.0;
      x = x.clamp(0.0, 1.0);
      return L * (vA * x + (vB - vA) * smoothInt(x));
    }

    final L01 = t1;
    final L12 = t2 - t1;
    final L23 = t3 - t2;
    final L34 = 1.0 - t3;

    final total = segFull(0.0, 1.0, L01) +
        segFull(1.0, peak, L12) +
        segFull(peak, 1.0, L23) +
        segFull(1.0, 0.0, L34);

    if (total <= 1e-9) return t;

    double acc = 0.0;

    if (t < t1 && L01 > 0.0) {
      final x = t / L01;
      acc += segPartial(0.0, 1.0, L01, x);
      return (acc / total).clamp(0.0, 1.0);
    } else {
      acc += segFull(0.0, 1.0, L01);
    }

    if (t < t2 && L12 > 0.0) {
      final x = (t - t1) / L12;
      acc += segPartial(1.0, peak, L12, x);
      return (acc / total).clamp(0.0, 1.0);
    } else {
      acc += segFull(1.0, peak, L12);
    }

    if (t < t3 && L23 > 0.0) {
      final x = (t - t2) / L23;
      acc += segPartial(peak, 1.0, L23, x);
      return (acc / total).clamp(0.0, 1.0);
    } else {
      acc += segFull(peak, 1.0, L23);
    }

    if (t < 1.0 && L34 > 0.0) {
      final x = (t - t3) / L34;
      acc += segPartial(1.0, 0.0, L34, x);
      return (acc / total).clamp(0.0, 1.0);
    }

    return 1.0;
  }

  int _findIndexForCost(List<double> cumCost, double target) {
    final last = cumCost.length - 1;
    if (last <= 0) return 0;
    if (target >= cumCost[last]) return last;

    int lo = 1, hi = last, ans = 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cumCost[mid] <= target) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// Compute the board transform used for painter and overlays.
  static WhiteboardViewportTransform computeViewportTransform(
    Size size, {
    required double boardWidth,
    required double boardHeight,
    double padding = 10.0,
    double shrinkFactor = 0.45,
  }) {
    final bounds = Rect.fromLTWH(
      -boardWidth / 2.0,
      -boardHeight / 2.0,
      boardWidth,
      boardHeight,
    );
    final scale = _computeUniformScaleForBounds(
      bounds,
      size,
      padding: padding,
      shrinkFactor: shrinkFactor,
    );
    final tx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty = (size.height - bounds.height * scale) / 2 - bounds.top * scale;
    return WhiteboardViewportTransform(
      scale: scale,
      translateX: tx,
      translateY: ty,
    );
  }

  static double _computeUniformScaleForBounds(
    Rect bounds,
    Size size, {
    required double padding,
    required double shrinkFactor,
  }) {
    final sx = (size.width - 2 * padding) / bounds.width;
    final sy = (size.height - 2 * padding) / bounds.height;
    final v = math.min(sx, sy);
    final fit = (v.isFinite && v > 0) ? v : 1.0;
    return fit * shrinkFactor;
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter old) =>
      old.staticStrokes != staticStrokes ||
      old.animStrokes != animStrokes ||
      old.animationT != animationT ||
      old.basePenWidth != basePenWidth ||
      old.stepMode != stepMode ||
      old.stepStrokeCount != stepStrokeCount ||
      old.boardWidth != boardWidth ||
      old.boardHeight != boardHeight ||
      old.strokeColor != strokeColor ||
      old.useStrokeColors != useStrokeColors ||
      old.speedStartPct != speedStartPct ||
      old.speedEndPct != speedEndPct ||
      old.speedPeakMult != speedPeakMult ||
      old.speedPeakTime != speedPeakTime;
}
