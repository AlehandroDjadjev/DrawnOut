import 'stroke_plan.dart';

/// A committed, persistent vector object on the whiteboard.
///
/// Contains a [StrokePlan] along with style parameters frozen at commit time.
/// Used to store completed drawings that should persist on the board.
class VectorObject {
  final StrokePlan plan;

  /// Base stroke width in pixels
  final double baseWidth;

  /// Opacity for each rendering pass (0.0 - 1.0)
  final double passOpacity;

  /// Number of rendering passes for hand-drawn effect
  final int passes;

  /// Jitter amplitude for hand-drawn wobble effect
  final double jitterAmp;

  /// Jitter frequency (samples per pixel of path length)
  final double jitterFreq;

  VectorObject({
    required this.plan,
    required this.baseWidth,
    required this.passOpacity,
    required this.passes,
    required this.jitterAmp,
    required this.jitterFreq,
  });
}
