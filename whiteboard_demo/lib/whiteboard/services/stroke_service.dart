import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Service for stroke manipulation operations.
///
/// Provides filtering, stitching, normalization, and sorting operations
/// for stroke data (lists of polyline points).
class StrokeService {
  const StrokeService();

  /// Filter strokes that are too short or have tiny spatial extent.
  ///
  /// Useful for removing noise/specks from vectorized content.
  ///
  /// - [minLength]: Minimum total path length in pixels
  /// - [minExtent]: Minimum bounding box dimension (width or height)
  List<List<Offset>> filterStrokes(
    List<List<Offset>> strokes, {
    double minLength = 24.0,
    double minExtent = 8.0,
  }) {
    final out = <List<Offset>>[];
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
        out.add(stroke);
      }
    }
    return out;
  }

  /// Connect stroke endpoints that are close together.
  ///
  /// Reduces visual gaps in contours by merging strokes whose
  /// endpoints are within [maxGap] pixels of each other.
  List<List<Offset>> stitchStrokes(
    List<List<Offset>> strokes, {
    double maxGap = 3.0,
  }) {
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

        if (dStart < best) {
          best = dStart;
          bestIdx = i;
          reverse = false;
        }
        if (dEnd < best) {
          best = dEnd;
          bestIdx = i;
          reverse = true;
        }
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

  /// Normalize stroke direction to left-to-right.
  ///
  /// Reverses strokes that go right-to-left so all strokes
  /// are drawn in a consistent direction.
  List<List<Offset>> normalizeDirection(List<List<Offset>> strokes) {
    return strokes.map((s) {
      if (s.isEmpty) return s;
      return s.first.dx <= s.last.dx ? s : s.reversed.toList();
    }).toList();
  }

  /// Sort strokes by their leftmost x position.
  ///
  /// Ensures strokes are drawn in reading order (left to right).
  List<List<Offset>> sortByXPosition(List<List<Offset>> strokes) {
    final sorted = List<List<Offset>>.from(strokes);
    sorted.sort((a, b) {
      if (a.isEmpty || b.isEmpty) return 0;
      final ax = a.map((p) => p.dx).reduce(math.min);
      final bx = b.map((p) => p.dx).reduce(math.min);
      return ax.compareTo(bx);
    });
    return sorted;
  }

  /// Apply offset to all strokes.
  ///
  /// Translates all stroke points by the given offset.
  List<List<Offset>> applyOffset(List<List<Offset>> strokes, Offset offset) {
    return strokes
        .map((s) => s.map((p) => p + offset).toList())
        .toList();
  }

  /// Scale all strokes by a factor.
  ///
  /// Multiplies all stroke points by the given scale factor.
  List<List<Offset>> applyScale(List<List<Offset>> strokes, double scale) {
    return strokes
        .map((s) => s.map((p) => p * scale).toList())
        .toList();
  }

  /// Process strokes for text rendering.
  ///
  /// Combines normalization, sorting, and stitching in one operation.
  /// This is the typical pipeline for text-derived strokes.
  ///
  /// - [maxGap]: Maximum gap for stitching (should be scaled by font size)
  List<List<Offset>> processTextStrokes(
    List<List<Offset>> strokes, {
    double maxGap = 3.0,
  }) {
    final normalized = normalizeDirection(strokes);
    final sorted = sortByXPosition(normalized);
    final stitched = stitchStrokes(sorted, maxGap: maxGap);
    return stitched;
  }

  /// Process strokes for diagram rendering.
  ///
  /// Applies filtering to remove noise and small artifacts.
  ///
  /// - [minLength]: Minimum stroke length
  /// - [minExtent]: Minimum bounding box dimension
  List<List<Offset>> processDiagramStrokes(
    List<List<Offset>> strokes, {
    double minLength = 24.0,
    double minExtent = 8.0,
  }) {
    return filterStrokes(strokes, minLength: minLength, minExtent: minExtent);
  }

  /// Calculate total length of all strokes.
  double totalLength(List<List<Offset>> strokes) {
    double length = 0.0;
    for (final stroke in strokes) {
      for (int i = 1; i < stroke.length; i++) {
        length += (stroke[i] - stroke[i - 1]).distance;
      }
    }
    return length;
  }

  /// Calculate bounding box of all strokes.
  Rect? boundingBox(List<List<Offset>> strokes) {
    if (strokes.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final stroke in strokes) {
      for (final point in stroke) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}
