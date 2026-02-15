import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/vector_object.dart';
import '../core/placed_image.dart';

/// Paints all committed vector objects on the whiteboard.
///
/// This painter renders with a transparent background so it can be
/// layered on top of other content. Each object is rendered with
/// its own style settings (passes, jitter, etc.).
class CommittedPainter extends CustomPainter {
  /// List of committed vector objects to render
  final List<VectorObject> objects;

  /// Stroke color for all objects (default black)
  final Color strokeColor;

  const CommittedPainter(
    this.objects, {
    this.strokeColor = Colors.black,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);

    for (int i = 0; i < objects.length; i++) {
      final obj = objects[i];
      _drawStyledPath(
        canvas,
        obj.plan.toPath(),
        passes: obj.passes,
        passOpacity: obj.passOpacity,
        baseWidth: obj.baseWidth,
        jitterAmp: obj.jitterAmp,
        jitterFreq: obj.jitterFreq,
        seedBase: 9001 + i * 67,
      );
    }

    canvas.restore();
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
  }) {
    for (int k = 0; k < passes; k++) {
      final noisyPath = _jitterPath(
        path,
        amp: jitterAmp,
        freq: jitterFreq,
        seed: seedBase + k * 97,
      );

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
  }

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
  bool shouldRepaint(covariant CommittedPainter old) {
    return old.objects != objects || old.strokeColor != strokeColor;
  }
}

/// Paints only raster images without any vector strokes.
///
/// Use this to render image underlays separately from strokes.
class RasterOnlyPainter extends CustomPainter {
  /// List of raster images to render
  final List<PlacedImage> images;

  /// Pan offset for the canvas
  final Offset pan;

  /// Zoom level for the canvas
  final double zoom;

  /// Background color (default white)
  final Color backgroundColor;

  const RasterOnlyPainter({
    required this.images,
    this.pan = Offset.zero,
    this.zoom = 1.0,
    this.backgroundColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    if (images.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx + pan.dx, center.dy + pan.dy);
    canvas.scale(zoom);

    for (final img in images) {
      final topLeft = img.worldCenter -
          Offset(
            img.worldSize.width / 2,
            img.worldSize.height / 2,
          );
      final destRect = topLeft & img.worldSize;
      final srcRect = img.sourceRect;

      final paint = Paint()
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withOpacity(img.opacity);

      canvas.drawImageRect(img.image, srcRect, destRect, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RasterOnlyPainter old) {
    return old.images != images ||
        old.pan != pan ||
        old.zoom != zoom ||
        old.backgroundColor != backgroundColor;
  }
}

/// A combined painter that renders both raster images and vector objects.
class CombinedWhiteboardPainter extends CustomPainter {
  final List<PlacedImage> images;
  final List<VectorObject> objects;
  final Path? animatingPath;
  final double animProgress;
  final Offset pan;
  final double zoom;
  final Color backgroundColor;
  final Color strokeColor;
  final double rasterVeilOpacity;

  const CombinedWhiteboardPainter({
    this.images = const [],
    this.objects = const [],
    this.animatingPath,
    this.animProgress = 1.0,
    this.pan = Offset.zero,
    this.zoom = 1.0,
    this.backgroundColor = Colors.white,
    this.strokeColor = Colors.black,
    this.rasterVeilOpacity = 0.35,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx + pan.dx, center.dy + pan.dy);
    canvas.scale(zoom);

    // Draw raster images first (underlay)
    for (final img in images) {
      _drawImage(canvas, img);
    }

    // Draw committed vector objects
    for (int i = 0; i < objects.length; i++) {
      _drawVectorObject(canvas, objects[i], 9001 + i * 67);
    }

    // Draw animating path if present
    if (animatingPath != null && animProgress > 0) {
      _drawAnimatingPath(canvas, animatingPath!);
    }

    canvas.restore();
  }

  void _drawImage(Canvas canvas, PlacedImage img) {
    final topLeft = img.worldCenter -
        Offset(
          img.worldSize.width / 2,
          img.worldSize.height / 2,
        );
    final destRect = topLeft & img.worldSize;

    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..color = Colors.white.withOpacity(img.opacity);
    canvas.drawImageRect(img.image, img.sourceRect, destRect, paint);

    // Veil overlay
    if (rasterVeilOpacity > 0) {
      canvas.drawRect(destRect,
          Paint()..color = Colors.white.withOpacity(rasterVeilOpacity));
    }
  }

  void _drawVectorObject(Canvas canvas, VectorObject obj, int seedBase) {
    final path = obj.plan.toPath();

    for (int k = 0; k < obj.passes; k++) {
      final noisyPath =
          _jitterPath(path, obj.jitterAmp, obj.jitterFreq, seedBase + k * 97);
      final widthMult = 1.0 + (k == 0 ? 0.0 : -0.15 * k);

      canvas.drawPath(
        noisyPath,
        Paint()
          ..color = strokeColor.withOpacity(obj.passOpacity.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = (obj.baseWidth * widthMult).clamp(0.5, 100.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  void _drawAnimatingPath(Canvas canvas, Path path) {
    // Default style for animating content
    const passes = 2;
    const passOpacity = 0.8;
    const baseWidth = 2.5;
    const jitterAmp = 0.9;
    const jitterFreq = 0.3;

    for (int k = 0; k < passes; k++) {
      final noisyPath = _jitterPath(path, jitterAmp, jitterFreq, 1337 + k * 97);
      final widthMult = 1.0 + (k == 0 ? 0.0 : -0.15 * k);

      canvas.drawPath(
        noisyPath,
        Paint()
          ..color = strokeColor.withOpacity(passOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (baseWidth * widthMult).clamp(0.5, 100.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  Path _jitterPath(Path p, double amp, double freq, int seed) {
    if (amp <= 0 || freq <= 0) return p;
    final rnd = math.Random(seed);
    final out = Path();

    for (final m in p.computeMetrics()) {
      final nSamples = (m.length * freq).clamp(8, 20000).toInt();
      for (int i = 0; i <= nSamples; i++) {
        final d = m.length * (i / nSamples);
        final tangent = m.getTangentForOffset(d);
        if (tangent == null) continue;
        final pos = tangent.position;
        final q = pos +
            Offset(
              (rnd.nextDouble() - 0.5) * 2.0 * amp,
              (rnd.nextDouble() - 0.5) * 2.0 * amp,
            );
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
  bool shouldRepaint(covariant CombinedWhiteboardPainter old) {
    return old.images != images ||
        old.objects != objects ||
        old.animatingPath != animatingPath ||
        old.animProgress != animProgress ||
        old.pan != pan ||
        old.zoom != zoom;
  }
}
