import 'dart:math' as math;
import 'dart:ui';

/// A plan of strokes to be drawn, represented as lists of points.
///
/// This class manages a collection of strokes and provides utilities
/// for calculating total length, filtering, and converting to Flutter Path.
class StrokePlan {
  final List<List<Offset>> strokes;

  StrokePlan(this.strokes);

  /// Whether the plan has no strokes
  bool get isEmpty => strokes.isEmpty;

  /// Whether the plan has strokes
  bool get isNotEmpty => strokes.isNotEmpty;

  /// Number of strokes in the plan
  int get strokeCount => strokes.length;

  /// Calculate the total length of all strokes
  double totalLength() {
    double length = 0.0;
    for (final stroke in strokes) {
      for (int i = 1; i < stroke.length; i++) {
        length += (stroke[i] - stroke[i - 1]).distance;
      }
    }
    return length;
  }

  /// Calculate the bounding box of all strokes
  Rect? get bounds {
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

  /// Filter out strokes that are too short or have too small extent.
  ///
  /// This is useful for removing decorative/noise strokes from diagrams.
  ///
  /// [minLength] - Minimum total path length for a stroke to be kept
  /// [minExtent] - Minimum bounding box extent (max of width/height)
  StrokePlan filterStrokes({
    double minLength = 24.0,
    double minExtent = 8.0,
  }) {
    final filtered = <List<Offset>>[];

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;

      // Calculate length and extent
      double length = 0.0;
      double strokeMinX = stroke.first.dx;
      double strokeMaxX = stroke.first.dx;
      double strokeMinY = stroke.first.dy;
      double strokeMaxY = stroke.first.dy;

      for (int i = 1; i < stroke.length; i++) {
        length += (stroke[i] - stroke[i - 1]).distance;
        final px = stroke[i].dx;
        final py = stroke[i].dy;
        if (px < strokeMinX) strokeMinX = px;
        if (px > strokeMaxX) strokeMaxX = px;
        if (py < strokeMinY) strokeMinY = py;
        if (py > strokeMaxY) strokeMaxY = py;
      }

      final extent = math.max(strokeMaxX - strokeMinX, strokeMaxY - strokeMinY);

      if (length >= minLength && extent >= minExtent) {
        filtered.add(stroke);
      }
    }

    return StrokePlan(filtered);
  }

  /// Convert all strokes to a single Flutter Path
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

  /// Extract a partial path up to a certain length (for animation)
  Path extractPartialPath(double targetLength) {
    final fullPath = toPath();
    final out = Path();
    double accumulated = 0.0;

    for (final metric in fullPath.computeMetrics()) {
      if (accumulated >= targetLength) break;
      final remain = targetLength - accumulated;
      final take = remain >= metric.length ? metric.length : remain;
      if (take > 0) {
        out.addPath(metric.extractPath(0, take), Offset.zero);
        accumulated += take;
      }
    }

    return out;
  }

  /// Create a new StrokePlan with strokes translated by an offset
  StrokePlan translate(Offset offset) {
    return StrokePlan(
      strokes.map((stroke) {
        return stroke.map((point) => point + offset).toList();
      }).toList(),
    );
  }

  /// Create a new StrokePlan with strokes scaled by a factor
  StrokePlan scale(double factor, {Offset origin = Offset.zero}) {
    return StrokePlan(
      strokes.map((stroke) {
        return stroke.map((point) {
          return Offset(
            (point.dx - origin.dx) * factor + origin.dx,
            (point.dy - origin.dy) * factor + origin.dy,
          );
        }).toList();
      }).toList(),
    );
  }

  /// Create a copy of this StrokePlan
  StrokePlan copy() {
    return StrokePlan(
      strokes.map((stroke) => List<Offset>.from(stroke)).toList(),
    );
  }

  @override
  String toString() => 'StrokePlan(${strokes.length} strokes, ${totalLength().toStringAsFixed(1)} length)';
}
