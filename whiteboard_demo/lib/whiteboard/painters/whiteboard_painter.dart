import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/drawable_stroke.dart';

/// Custom painter for rendering whiteboard strokes with animation
class WhiteboardPainter extends CustomPainter {
  final List<DrawableStroke> staticStrokes;
  final List<DrawableStroke> animStrokes;
  final double animationT;
  final double basePenWidth;
  final bool stepMode;
  final int stepStrokeCount;
  final double boardWidth;
  final double boardHeight;
  final Color strokeColor;

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
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (staticStrokes.isEmpty && animStrokes.isEmpty) return;

    final allStrokes = <DrawableStroke>[
      ...staticStrokes,
      ...animStrokes,
    ];

    final bounds = _computeBounds();
    final scale = _computeUniformScale(bounds, size, padding: 80);
    final tx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
    final ty = (size.height - bounds.height * scale) / 2 - bounds.top * scale;

    canvas.save();
    canvas.translate(tx, ty);
    canvas.scale(scale);

    if (stepMode) {
      final count = stepStrokeCount.clamp(0, allStrokes.length);
      for (int i = 0; i < count; i++) {
        _drawStroke(canvas, allStrokes[i], 1.0, scale);
      }
    } else {
      // Draw all static strokes fully
      for (final s in staticStrokes) {
        _drawStroke(canvas, s, 1.0, scale);
      }

      // Draw animated strokes with timing
      if (animStrokes.isNotEmpty) {
        final totalWeight = animStrokes.fold<double>(0.0, (s, d) => s + d.timeWeight);
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

  void _drawStroke(Canvas canvas, DrawableStroke stroke, double phase, double viewScale) {
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
      final targetCost = drawPhase * totalCost;
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

    final paintLine = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = penW;

    canvas.drawPath(path, paintLine);
  }

  int _findIndexForCost(List<double> cumCost, double target) {
    final last = cumCost.length - 1;
    if (last <= 0) return 0;
    if (target >= cumCost[last]) return last;

    int lo = 1;
    int hi = last;
    int ans = 1;
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

  Rect _computeBounds() {
    final double halfW = boardWidth / 2.0;
    final double halfH = boardHeight / 2.0;
    return Rect.fromLTWH(-halfW, -halfH, boardWidth, boardHeight);
  }

  double _computeUniformScale(Rect bounds, Size size, {double padding = 10}) {
    final sx = (size.width - 2 * padding) / bounds.width;
    final sy = (size.height - 2 * padding) / bounds.height;
    final v = math.min(sx, sy);
    final fit = (v.isFinite && v > 0) ? v : 1.0;
    const shrinkFactor = 0.45;
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
      old.strokeColor != strokeColor;
}
