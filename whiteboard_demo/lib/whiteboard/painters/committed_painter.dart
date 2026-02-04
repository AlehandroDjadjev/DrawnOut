import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/vector_object.dart';

/// Paints all committed vector objects with transparent background.
///
/// This painter is layered on top of other painters to show
/// previously committed drawings that persist on the board.
class CommittedPainter extends CustomPainter {
  final List<VectorObject> objects;

  const CommittedPainter(this.objects);

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
      final noisy = _jitterPath(path,
          amp: jitterAmp, freq: jitterFreq, seed: seedBase + k * 97);
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
  bool shouldRepaint(covariant CommittedPainter old) => old.objects != objects;
}
