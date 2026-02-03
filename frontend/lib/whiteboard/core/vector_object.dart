import 'stroke_plan.dart';

/// Style configuration for rendering vector objects
class VectorStyle {
  /// Base stroke width in pixels
  final double baseWidth;

  /// Opacity for each render pass (0.0 - 1.0)
  final double passOpacity;

  /// Number of render passes for hand-drawn effect
  final int passes;

  /// Amplitude of jitter for hand-drawn effect
  final double jitterAmp;

  /// Frequency of jitter sampling
  final double jitterFreq;

  const VectorStyle({
    this.baseWidth = 2.5,
    this.passOpacity = 0.8,
    this.passes = 2,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.3,
  });

  /// Default style with standard hand-drawn effect
  static const VectorStyle defaultStyle = VectorStyle();

  /// Clean style with no jitter (for precise rendering)
  static const VectorStyle clean = VectorStyle(
    passes: 1,
    passOpacity: 1.0,
    jitterAmp: 0.0,
    jitterFreq: 0.0,
  );

  /// Bold style with thicker strokes
  static const VectorStyle bold = VectorStyle(
    baseWidth: 4.0,
    passes: 2,
    passOpacity: 0.9,
    jitterAmp: 0.6,
    jitterFreq: 0.25,
  );

  /// Light style with thinner strokes
  static const VectorStyle light = VectorStyle(
    baseWidth: 1.5,
    passes: 1,
    passOpacity: 0.7,
    jitterAmp: 0.5,
    jitterFreq: 0.35,
  );

  VectorStyle copyWith({
    double? baseWidth,
    double? passOpacity,
    int? passes,
    double? jitterAmp,
    double? jitterFreq,
  }) {
    return VectorStyle(
      baseWidth: baseWidth ?? this.baseWidth,
      passOpacity: passOpacity ?? this.passOpacity,
      passes: passes ?? this.passes,
      jitterAmp: jitterAmp ?? this.jitterAmp,
      jitterFreq: jitterFreq ?? this.jitterFreq,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VectorStyle &&
        other.baseWidth == baseWidth &&
        other.passOpacity == passOpacity &&
        other.passes == passes &&
        other.jitterAmp == jitterAmp &&
        other.jitterFreq == jitterFreq;
  }

  @override
  int get hashCode => Object.hash(baseWidth, passOpacity, passes, jitterAmp, jitterFreq);
}

/// A committed, persistent vector object on the whiteboard.
///
/// Once committed, the style is frozen and the object can be rendered
/// as part of the static board content.
class VectorObject {
  /// The stroke plan containing all strokes for this object
  final StrokePlan plan;

  /// The style used to render this object
  final VectorStyle style;

  /// Optional identifier for this object (for grouping/erasing)
  final String? id;

  /// Optional name for display purposes
  final String? name;

  VectorObject({
    required this.plan,
    VectorStyle? style,
    this.id,
    this.name,
  }) : style = style ?? VectorStyle.defaultStyle;

  /// Create a VectorObject with explicit style parameters (legacy compatibility)
  factory VectorObject.withParams({
    required StrokePlan plan,
    required double baseWidth,
    required double passOpacity,
    required int passes,
    required double jitterAmp,
    required double jitterFreq,
    String? id,
    String? name,
  }) {
    return VectorObject(
      plan: plan,
      style: VectorStyle(
        baseWidth: baseWidth,
        passOpacity: passOpacity,
        passes: passes,
        jitterAmp: jitterAmp,
        jitterFreq: jitterFreq,
      ),
      id: id,
      name: name,
    );
  }

  // Convenience getters for style properties
  double get baseWidth => style.baseWidth;
  double get passOpacity => style.passOpacity;
  int get passes => style.passes;
  double get jitterAmp => style.jitterAmp;
  double get jitterFreq => style.jitterFreq;

  /// Whether this object has any strokes
  bool get isEmpty => plan.isEmpty;

  /// Whether this object has strokes
  bool get isNotEmpty => plan.isNotEmpty;

  /// Create a copy with a new style
  VectorObject withStyle(VectorStyle newStyle) {
    return VectorObject(
      plan: plan,
      style: newStyle,
      id: id,
      name: name,
    );
  }

  @override
  String toString() => 'VectorObject(${id ?? 'unnamed'}, ${plan.strokeCount} strokes)';
}
