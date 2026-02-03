import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/placed_image.dart';

/// Paints an animated sketch with multi-pass jitter effect.
///
/// Renders a partial path with optional raster image underlay.
/// Uses multiple passes with jitter to create a hand-drawn appearance.
class SketchPainter extends CustomPainter {
  final Path partialWorldPath;
  final PlacedImage? raster;
  final int passes;
  final double passOpacity;
  final double baseWidth;
  final double jitterAmp;
  final double jitterFreq;

  const SketchPainter({
    required this.partialWorldPath,
    required this.raster,
    required this.passes,
    required this.passOpacity,
    required this.baseWidth,
    required this.jitterAmp,
    required this.jitterFreq,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw white background
    final bg = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, bg);

    final center = Offset(size.width / 2, size.height / 2);

    // Draw raster underlay if present
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
        ..color = Colors.white.withOpacity(1.0);
      canvas.drawImageRect(p.image, src, dest, imgPaint);
      // Semi-transparent veil over image
      final veil = Paint()..color = Colors.white.withOpacity(0.35);
      canvas.drawRect(dest, veil);
    }

    // Translate to center-origin coordinate system
    canvas.translate(center.dx, center.dy);

    // Draw multiple passes with jitter for hand-drawn effect
    for (int k = 0; k < passes; k++) {
      final seed = 1337 + k * 97;
      final noisy = _jitterPath(partialWorldPath,
          amp: jitterAmp, freq: jitterFreq, seed: seed);

      final paint = Paint()
        ..color = Colors.black.withOpacity(passOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            (baseWidth * (1.0 + (k == 0 ? 0.0 : -0.15 * k))).clamp(0.5, 100.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(noisy, paint);
    }
  }

  /// Apply jitter/wobble to a path for hand-drawn effect.
  Path _jitterPath(Path p,
      {required double amp, required double freq, required int seed}) {
    if (amp <= 0 || freq <= 0) return p;
    final rnd = math.Random(seed);
    final out = Path();
    for (final m in p.computeMetrics()) {
      final nSamples = (m.length * freq).clamp(8, 20000).toInt();
      for (int i = 0; i <= nSamples; i++) {
        final d = m.length * (i / nSamples);
        final pos = m.getTangentForOffset(d)!.position;
        final dx = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final dy = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final q = pos + Offset(dx, dy);
        if (i == 0) {
          out.moveTo(q.dx, q.dy);
        } else {
          out.lineTo(q.dx, q.dy);
        }
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant SketchPainter old) {
    return old.partialWorldPath != partialWorldPath ||
        old.raster != raster ||
        old.passes != passes ||
        old.passOpacity != passOpacity ||
        old.baseWidth != baseWidth ||
        old.jitterAmp != jitterAmp ||
        old.jitterFreq != jitterFreq;
  }
}
