import 'dart:ui';

/// Raw polyline stroke data - list of connected points
class StrokePolyline {
  final List<Offset> points;
  const StrokePolyline(this.points);
}

/// Single cubic Bezier segment with 4 control points
class CubicSegment {
  final Offset p0; // Start point
  final Offset c1; // First control point
  final Offset c2; // Second control point
  final Offset p1; // End point

  const CubicSegment({
    required this.p0,
    required this.c1,
    required this.c2,
    required this.p1,
  });

  /// Evaluate point on curve at parameter t (0-1)
  Offset evaluate(double t) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    final x = mt2 * mt * p0.dx +
        3 * mt2 * t * c1.dx +
        3 * mt * t2 * c2.dx +
        t2 * t * p1.dx;
    final y = mt2 * mt * p0.dy +
        3 * mt2 * t * c1.dy +
        3 * mt * t2 * c2.dy +
        t2 * t * p1.dy;
    return Offset(x, y);
  }
}

/// Stroke composed of multiple cubic Bezier segments
class StrokeCubic {
  final List<CubicSegment> segments;
  const StrokeCubic(this.segments);

  /// Sample the entire stroke into points
  List<Offset> sample({double upscale = 1.0, int stepsPerSegment = 18}) {
    final pts = <Offset>[];
    bool first = true;

    for (final seg in segments) {
      for (int i = 0; i <= stepsPerSegment; i++) {
        final t = i / stepsPerSegment;
        final p = seg.evaluate(t);
        final q = Offset(p.dx * upscale, p.dy * upscale);
        if (!first) {
          if ((q - pts.last).distance < 0.05) continue;
        }
        pts.add(q);
        first = false;
      }
    }
    return pts;
  }
}

/// Cached glyph data with cubic strokes and bounds
class GlyphData {
  final List<StrokeCubic> cubics;
  final Rect bounds;

  const GlyphData({
    required this.cubics,
    required this.bounds,
  });
}
