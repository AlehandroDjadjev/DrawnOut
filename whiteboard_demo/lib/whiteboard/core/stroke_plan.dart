import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A plan of strokes (polylines) to be drawn/animated.
///
/// Each stroke is a list of [Offset] points representing a continuous path.
/// Matches visual_whiteboard: single-pass drawing, optional deterministic wobble.
class StrokePlan {
  final List<List<Offset>> strokes;

  StrokePlan(List<List<Offset>> strokes, {double wobbleAmp = 0.8})
      : strokes = wobbleAmp > 0
            ? strokes
                .where((s) => s.length >= 2)
                .map((s) => _applyWobble(s, wobbleAmp))
                .toList()
            : strokes.where((s) => s.length >= 2).toList();

  /// Deterministic perpendicular wobble matching visual_whiteboard _applyWobble.
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
      final combined = 0.6 * waveFast + 0.4 * waveSlow;
      final w = combined * amp * fade;
      out.add(Offset(pts[i].dx + nx * w, pts[i].dy + ny * w));
    }
    return out;
  }

  bool get isEmpty => strokes.isEmpty;

  /// Calculate the total length of all strokes combined.
  double totalLength() {
    double length = 0.0;
    for (final stroke in strokes) {
      for (int i = 1; i < stroke.length; i++) {
        length += (stroke[i] - stroke[i - 1]).distance;
      }
    }
    return length;
  }

  /// Convert all strokes to a single [Path] for rendering.
  Path toPath() {
    final path = Path();
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      path.moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
    }
    return path;
  }

  /// Filter strokes that are too short or have tiny spatial extent.
  ///
  /// Useful for removing noise/specks from vectorized diagrams.
  static List<List<Offset>> filterStrokes(
    List<List<Offset>> strokes, {
    double minLength = 24.0,
    double minExtent = 8.0,
  }) {
    final filtered = <List<Offset>>[];
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;

      double len = 0.0;
      double minX = stroke.first.dx,
          maxX = stroke.first.dx,
          minY = stroke.first.dy,
          maxY = stroke.first.dy;

      for (int i = 1; i < stroke.length; i++) {
        len += (stroke[i] - stroke[i - 1]).distance;
        final px = stroke[i].dx, py = stroke[i].dy;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }

      final extent = math.max(maxX - minX, maxY - minY);
      if (len >= minLength && extent >= minExtent) {
        filtered.add(stroke);
      }
    }
    return filtered;
  }
}
