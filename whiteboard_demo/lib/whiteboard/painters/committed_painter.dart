import 'package:flutter/material.dart';
import '../core/vector_object.dart';

/// Paints committed vector objects — single-pass drawing matching visual_whiteboard.
///
/// Uses clean stroke rendering (no multi-pass jitter, no fuzzy doubling).
class CommittedPainter extends CustomPainter {
  final List<VectorObject> objects;

  const CommittedPainter(this.objects);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);

    for (final obj in objects) {
      // Single pass — match visual_whiteboard WhiteboardPainter._drawStroke
      final paint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = obj.baseWidth.clamp(0.5, 20.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(obj.plan.toPath(), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CommittedPainter old) => old.objects != objects;
}
