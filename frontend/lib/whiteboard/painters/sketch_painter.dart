import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/placed_image.dart';

/// A custom painter for drawing animated sketch strokes with a hand-drawn effect.
///
/// This painter renders strokes with multi-pass jitter to create an organic,
/// hand-drawn appearance. It supports an optional raster image underlay.
class SketchPainter extends CustomPainter {
  /// The partial path to render (for animation)
  final Path partialWorldPath;

  /// Optional raster image to show as underlay
  final PlacedImage? raster;

  /// Number of render passes for hand-drawn effect
  final int passes;

  /// Opacity for each render pass (0.0 - 1.0)
  final double passOpacity;

  /// Base stroke width in pixels
  final double baseWidth;

  /// Amplitude of jitter for hand-drawn effect
  final double jitterAmp;

  /// Frequency of jitter sampling (samples per pixel)
  final double jitterFreq;

  /// Background color (default white)
  final Color backgroundColor;

  /// Stroke color (default black)
  final Color strokeColor;

  /// Opacity for the raster image veil overlay
  final double rasterVeilOpacity;

  const SketchPainter({
    required this.partialWorldPath,
    this.raster,
    this.passes = 2,
    this.passOpacity = 0.8,
    this.baseWidth = 2.5,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.3,
    this.backgroundColor = Colors.white,
    this.strokeColor = Colors.black,
    this.rasterVeilOpacity = 0.35,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final center = Offset(size.width / 2, size.height / 2);

    // Draw raster image underlay if present
    if (raster != null) {
      _drawRasterUnderlay(canvas, center, raster!);
    }

    // Translate to center for world-space drawing
    canvas.translate(center.dx, center.dy);

    // Draw strokes with multi-pass jitter effect
    _drawStyledPath(
      canvas,
      partialWorldPath,
      passes: passes,
      passOpacity: passOpacity,
      baseWidth: baseWidth,
      jitterAmp: jitterAmp,
      jitterFreq: jitterFreq,
      seedBase: 1337,
      color: strokeColor,
    );
  }

  void _drawRasterUnderlay(Canvas canvas, Offset center, PlacedImage img) {
    final topLeft = center +
        img.worldCenter -
        Offset(
          img.worldSize.width / 2,
          img.worldSize.height / 2,
        );
    final destRect = topLeft & img.worldSize;
    final srcRect = img.sourceRect;

    // Draw the image
    final imgPaint = Paint()
      ..filterQuality = FilterQuality.high
      ..color = Colors.white.withOpacity(img.opacity);
    canvas.drawImageRect(img.image, srcRect, destRect, imgPaint);

    // Draw a semi-transparent veil over the image
    if (rasterVeilOpacity > 0) {
      final veilPaint = Paint()
        ..color = Colors.white.withOpacity(rasterVeilOpacity);
      canvas.drawRect(destRect, veilPaint);
    }
  }

  void _drawStyledPath(
    Canvas canvas,
    Path path, {
    required int passes,
    required double passOpacity,
    required double baseWidth,
    required double jitterAmp,
    required double jitterFreq,
    required int seedBase,
    required Color color,
  }) {
    for (int k = 0; k < passes; k++) {
      final seed = seedBase + k * 97;
      final noisyPath = _jitterPath(
        path,
        amp: jitterAmp,
        freq: jitterFreq,
        seed: seed,
      );

      // Each pass is slightly thinner and offset
      final widthMultiplier = 1.0 + (k == 0 ? 0.0 : -0.15 * k);
      final strokeWidth = (baseWidth * widthMultiplier).clamp(0.5, 100.0);

      final paint = Paint()
        ..color = color.withOpacity(passOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(noisyPath, paint);
    }
  }

  /// Apply jitter to a path for hand-drawn effect
  Path _jitterPath(
    Path p, {
    required double amp,
    required double freq,
    required int seed,
  }) {
    if (amp <= 0 || freq <= 0) return p;

    final rnd = math.Random(seed);
    final out = Path();

    for (final metric in p.computeMetrics()) {
      final nSamples = (metric.length * freq).clamp(8, 20000).toInt();

      for (int i = 0; i <= nSamples; i++) {
        final distance = metric.length * (i / nSamples);
        final tangent = metric.getTangentForOffset(distance);
        if (tangent == null) continue;

        final pos = tangent.position;
        final dx = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final dy = (rnd.nextDouble() - 0.5) * 2.0 * amp;
        final jitteredPoint = pos + Offset(dx, dy);

        if (i == 0) {
          out.moveTo(jitteredPoint.dx, jitteredPoint.dy);
        } else {
          out.lineTo(jitteredPoint.dx, jitteredPoint.dy);
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
        old.jitterFreq != jitterFreq ||
        old.backgroundColor != backgroundColor ||
        old.strokeColor != strokeColor;
  }
}

/// A lighter version of SketchPainter that only draws the strokes
/// without background or raster underlay.
class SketchOverlayPainter extends CustomPainter {
  final Path partialWorldPath;
  final int passes;
  final double passOpacity;
  final double baseWidth;
  final double jitterAmp;
  final double jitterFreq;
  final Color strokeColor;
  final Offset center;

  const SketchOverlayPainter({
    required this.partialWorldPath,
    required this.center,
    this.passes = 2,
    this.passOpacity = 0.8,
    this.baseWidth = 2.5,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.3,
    this.strokeColor = Colors.black,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(center.dx, center.dy);

    for (int k = 0; k < passes; k++) {
      final seed = 1337 + k * 97;
      final noisyPath = _jitterPath(partialWorldPath,
          amp: jitterAmp, freq: jitterFreq, seed: seed);

      final widthMultiplier = 1.0 + (k == 0 ? 0.0 : -0.15 * k);
      final paint = Paint()
        ..color = strokeColor.withOpacity(passOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = (baseWidth * widthMultiplier).clamp(0.5, 100.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;

      canvas.drawPath(noisyPath, paint);
    }

    canvas.restore();
  }

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
  bool shouldRepaint(covariant SketchOverlayPainter old) {
    return old.partialWorldPath != partialWorldPath ||
        old.passes != passes ||
        old.passOpacity != passOpacity ||
        old.baseWidth != baseWidth ||
        old.jitterAmp != jitterAmp ||
        old.jitterFreq != jitterFreq;
  }
}
