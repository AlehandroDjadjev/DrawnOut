import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A plan of strokes (polylines) to be drawn/animated.
///
/// Each stroke is a list of [Offset] points representing a continuous path.
class StrokePlan {
  final List<List<Offset>> strokes;

  StrokePlan(this.strokes);

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
