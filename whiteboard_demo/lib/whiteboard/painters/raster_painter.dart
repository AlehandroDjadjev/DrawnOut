import 'package:flutter/material.dart';
import '../core/placed_image.dart';

/// Paints only a raster image (no strokes).
///
/// Used when displaying a reference image without any sketch animation.
class RasterOnlyPainter extends CustomPainter {
  final PlacedImage? raster;

  const RasterOnlyPainter({this.raster});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw white background
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    if (raster == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final p = raster!;
    final topLeft = center +
        p.worldCenter -
        Offset(p.worldSize.width / 2, p.worldSize.height / 2);
    final dest = topLeft & p.worldSize;
    final src = Rect.fromLTWH(
        0, 0, p.image.width.toDouble(), p.image.height.toDouble());
    final imgPaint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(p.image, src, dest, imgPaint);
  }

  @override
  bool shouldRepaint(covariant RasterOnlyPainter oldDelegate) =>
      oldDelegate.raster != raster;
}
