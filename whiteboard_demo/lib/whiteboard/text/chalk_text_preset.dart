import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Styling preset used for text-to-vector rendering.
///
/// Phase 1 intentionally stays raster->vector, but these presets improve
/// letterform personality, spacing, and chalk-like roughness.
class ChalkTextPreset {
  final String id;
  final String label;
  final String fontFamily;
  final FontWeight fontWeight;

  /// Letter spacing in "em" units (scaled by font size).
  final double letterSpacingEm;

  /// Line height multiplier used during text placement.
  final double lineHeightMultiplier;

  /// Extra text overdraw passes to produce rough chalk contours.
  final int texturePasses;

  /// Opacity for overdraw texture passes.
  final double textureAlpha;

  /// Pixel jitter amount for each overdraw pass, as em.
  final double textureJitterEm;

  /// Small per-line baseline wobble for a human writing feel.
  final double baselineJitterEm;

  /// Scales centerline switching threshold.
  final double centerlineThresholdScale;

  /// Scales centerline merge distance.
  final double centerlineMergeScale;

  /// Playback style multipliers for text-dominant plans.
  final double strokeWidthScale;
  final double opacityScale;
  final int passDelta;
  final double jitterAmpAdd;
  final double jitterFreq;

  /// If true, headings remain outline-oriented.
  final bool preferOutlineHeadings;

  const ChalkTextPreset({
    required this.id,
    required this.label,
    required this.fontFamily,
    this.fontWeight = FontWeight.w500,
    this.letterSpacingEm = 0.0,
    this.lineHeightMultiplier = 1.25,
    this.texturePasses = 1,
    this.textureAlpha = 0.22,
    this.textureJitterEm = 0.015,
    this.baselineJitterEm = 0.02,
    this.centerlineThresholdScale = 1.0,
    this.centerlineMergeScale = 1.0,
    this.strokeWidthScale = 1.0,
    this.opacityScale = 1.0,
    this.passDelta = 0,
    this.jitterAmpAdd = 0.0,
    this.jitterFreq = 0.025,
    this.preferOutlineHeadings = true,
  });

  TextStyle toTextStyle({
    required double fontSize,
    Color color = Colors.black,
    bool bold = false,
  }) {
    return TextStyle(
      color: color,
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: bold ? FontWeight.w700 : fontWeight,
      letterSpacing: letterSpacingEm * fontSize,
      height: lineHeightMultiplier,
    );
  }

  int effectiveTexturePasses(double strength) {
    final s = strength.clamp(0.0, 1.0);
    return (texturePasses * s).round();
  }

  double effectiveTextureAlpha(double strength) {
    final s = strength.clamp(0.0, 1.0);
    return (textureAlpha * (0.4 + 0.6 * s)).clamp(0.02, 0.5);
  }

  double textureJitterPx(double fontSize, double strength) {
    final s = strength.clamp(0.0, 1.0);
    return (textureJitterEm * fontSize * (0.35 + 0.65 * s)).clamp(0.2, 2.8);
  }

  double baselineJitterPx(double fontSize, int lineIndex) {
    if (baselineJitterEm <= 0) return 0.0;
    final amp = (baselineJitterEm * fontSize).clamp(0.0, 5.0);
    // Deterministic sinusoidal wobble keeps re-renders stable.
    return math.sin((lineIndex + 1) * 1.618) * amp;
  }

  static const String classicId = 'classic_chalk';
  static const String neatId = 'neat_teacher';
  static const String boldId = 'bold_marker';
  static const String quirkyId = 'quirky_brush';

  static const ChalkTextPreset classic = ChalkTextPreset(
    id: classicId,
    label: 'Classic Chalk',
    fontFamily: 'Schoolbell',
    fontWeight: FontWeight.w500,
    letterSpacingEm: 0.012,
    lineHeightMultiplier: 1.28,
    texturePasses: 2,
    textureAlpha: 0.22,
    textureJitterEm: 0.016,
    baselineJitterEm: 0.02,
    centerlineThresholdScale: 1.0,
    centerlineMergeScale: 1.0,
    strokeWidthScale: 1.08,
    opacityScale: 0.95,
    passDelta: 1,
    jitterAmpAdd: 0.35,
    jitterFreq: 0.024,
    preferOutlineHeadings: true,
  );

  static const ChalkTextPreset neatTeacher = ChalkTextPreset(
    id: neatId,
    label: 'Neat Teacher',
    fontFamily: 'PatrickHand',
    fontWeight: FontWeight.w500,
    letterSpacingEm: 0.01,
    lineHeightMultiplier: 1.24,
    texturePasses: 1,
    textureAlpha: 0.16,
    textureJitterEm: 0.012,
    baselineJitterEm: 0.012,
    centerlineThresholdScale: 0.95,
    centerlineMergeScale: 0.9,
    strokeWidthScale: 1.0,
    opacityScale: 1.0,
    passDelta: 0,
    jitterAmpAdd: 0.2,
    jitterFreq: 0.02,
    preferOutlineHeadings: true,
  );

  static const ChalkTextPreset boldMarker = ChalkTextPreset(
    id: boldId,
    label: 'Bold Marker',
    fontFamily: 'PermanentMarker',
    fontWeight: FontWeight.w500,
    letterSpacingEm: 0.014,
    lineHeightMultiplier: 1.22,
    texturePasses: 1,
    textureAlpha: 0.12,
    textureJitterEm: 0.009,
    baselineJitterEm: 0.01,
    centerlineThresholdScale: 0.8,
    centerlineMergeScale: 0.82,
    strokeWidthScale: 1.18,
    opacityScale: 1.05,
    passDelta: 0,
    jitterAmpAdd: 0.15,
    jitterFreq: 0.018,
    preferOutlineHeadings: true,
  );

  static const ChalkTextPreset quirkyBrush = ChalkTextPreset(
    id: quirkyId,
    label: 'Quirky Brush',
    fontFamily: 'CaveatBrush',
    fontWeight: FontWeight.w500,
    letterSpacingEm: 0.016,
    lineHeightMultiplier: 1.3,
    texturePasses: 2,
    textureAlpha: 0.18,
    textureJitterEm: 0.018,
    baselineJitterEm: 0.028,
    centerlineThresholdScale: 1.1,
    centerlineMergeScale: 1.08,
    strokeWidthScale: 1.06,
    opacityScale: 0.93,
    passDelta: 1,
    jitterAmpAdd: 0.4,
    jitterFreq: 0.028,
    preferOutlineHeadings: false,
  );

  static const List<ChalkTextPreset> all = [
    classic,
    neatTeacher,
    boldMarker,
    quirkyBrush,
  ];

  static ChalkTextPreset byId(String id) {
    return all.firstWhere(
      (preset) => preset.id == id,
      orElse: () => classic,
    );
  }
}
