import 'package:flutter/material.dart';
import '../core/placed_image.dart';

/// Paints an animated sketch — single-pass drawing matching visual_whiteboard.
///
/// Uses clean stroke rendering (no multi-pass jitter, no fuzzy doubling).
/// Renders partial path with optional raster image underlay.
class SketchPainter extends CustomPainter {
  final Path partialWorldPath;
  final PlacedImage? raster;
  final double baseWidth;

  const SketchPainter({
    required this.partialWorldPath,
    required this.raster,
    this.baseWidth = 4.0,
    // Ignored — visual_whiteboard uses single-pass, no jitter
    int passes = 1,
    double passOpacity = 1.0,
    double jitterAmp = 0.0,
    double jitterFreq = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    final center = Offset(size.width / 2, size.height / 2);

    if (raster != null) {
      final p = raster!;
      final topLeft = center +
          p.worldCenter -
          Offset(p.worldSize.width / 2, p.worldSize.height / 2);
      final dest = topLeft & p.worldSize;
      final src = Rect.fromLTWH(
          0, 0, p.image.width.toDouble(), p.image.height.toDouble());
      final imgPaint = Paint()
        ..filterQuality = FilterQuality.high
        ..color = Colors.white;
      canvas.drawImageRect(p.image, src, dest, imgPaint);
      final veil = Paint()..color = Colors.white.withOpacity(0.35);
      canvas.drawRect(dest, veil);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);

    // Single pass — match visual_whiteboard WhiteboardPainter._drawStroke
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth.clamp(0.5, 20.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(partialWorldPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SketchPainter old) {
    return old.partialWorldPath != partialWorldPath ||
        old.raster != raster ||
        old.baseWidth != baseWidth;
  }
}
