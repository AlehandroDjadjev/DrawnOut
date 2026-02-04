import 'dart:math' as math;

/// Configuration for font sizes by action type
class FontConfig {
  /// Font size for headings
  final double heading;

  /// Font size for body text (bullets, labels)
  final double body;

  /// Font size for formulas
  final double formula;

  /// Font size for small/fine print
  final double small;

  /// Minimum font size (applied after all calculations)
  final double minimum;

  const FontConfig({
    this.heading = 60.0,
    this.body = 60.0,
    this.formula = 60.0,
    this.small = 48.0,
    this.minimum = 36.0,
  });

  /// Default font configuration
  static const FontConfig defaultConfig = FontConfig();

  /// Get font size for a given action type
  ///
  /// [type] - The action type (heading, bullet, formula, etc.)
  /// [styleOverride] - Optional style map that may contain fontSize
  double forType(String type, {Map<String, dynamic>? styleOverride}) {
    // Check for explicit fontSize in style override
    if (styleOverride != null && styleOverride['fontSize'] is num) {
      return (styleOverride['fontSize'] as num).toDouble();
    }

    switch (type) {
      case 'heading':
        return heading;
      case 'formula':
        return formula;
      case 'small':
      case 'fine':
        return small;
      default:
        return body;
    }
  }

  /// Apply minimum font constraint
  double applyMinimum(double fontSize) {
    return math.max(fontSize, minimum);
  }

  FontConfig copyWith({
    double? heading,
    double? body,
    double? formula,
    double? small,
    double? minimum,
  }) {
    return FontConfig(
      heading: heading ?? this.heading,
      body: body ?? this.body,
      formula: formula ?? this.formula,
      small: small ?? this.small,
      minimum: minimum ?? this.minimum,
    );
  }
}

/// Configuration for indentation by action type and level
class IndentConfig {
  /// Indentation for level 1 bullets
  final double level1;

  /// Indentation for level 2 bullets
  final double level2;

  /// Indentation for level 3+ bullets
  final double level3;

  /// Additional indentation for subbullets beyond level 3
  final double subExtra;

  const IndentConfig({
    this.level1 = 32.0,
    this.level2 = 64.0,
    this.level3 = 96.0,
    this.subExtra = 24.0,
  });

  /// Default indentation configuration
  static const IndentConfig defaultConfig = IndentConfig();

  /// Get indentation for a given action type and level
  ///
  /// [type] - The action type (bullet, subbullet, etc.)
  /// [level] - The nesting level (1-based)
  double forType(String type, int level) {
    if (type == 'bullet') {
      if (level <= 1) return level1;
      if (level == 2) return level2;
      return level3;
    }
    if (type == 'subbullet') {
      if (level <= 1) return level2;
      if (level == 2) return level3;
      return level3 + subExtra;
    }
    return 0.0;
  }

  IndentConfig copyWith({
    double? level1,
    double? level2,
    double? level3,
    double? subExtra,
  }) {
    return IndentConfig(
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
      subExtra: subExtra ?? this.subExtra,
    );
  }
}

/// Configuration for centerline mode (used for small text)
///
/// Centerline mode produces cleaner strokes for small fonts by using
/// different vectorization parameters that create single-line strokes
/// instead of outlines.
class CenterlineConfig {
  /// Font size threshold below which centerline mode is used
  final double threshold;

  /// Epsilon value for path simplification (lower = more detail)
  final double epsilon;

  /// Resampling spacing (lower = denser points)
  final double resample;

  /// Factor for calculating merge distance (merge = fontSize * factor)
  final double mergeFactor;

  /// Minimum merge distance
  final double mergeMin;

  /// Maximum merge distance
  final double mergeMax;

  /// Number of smoothing passes
  final int smoothPasses;

  /// Whether headings should use outline mode even when below threshold
  final bool preferOutlineHeadings;

  const CenterlineConfig({
    this.threshold = 60.0,
    this.epsilon = 0.6,
    this.resample = 0.8,
    this.mergeFactor = 0.9,
    this.mergeMin = 12.0,
    this.mergeMax = 36.0,
    this.smoothPasses = 3,
    this.preferOutlineHeadings = true,
  });

  /// Default centerline configuration
  static const CenterlineConfig defaultConfig = CenterlineConfig();

  /// Check if centerline mode should be used for given font size
  bool shouldUseCenterline(double fontSize, {String? actionType}) {
    if (preferOutlineHeadings && actionType == 'heading') {
      return false;
    }
    return fontSize < threshold;
  }

  /// Get merge distance for a given font size
  double mergeDistanceFor(double fontSize) {
    if (fontSize < threshold) {
      return (fontSize * mergeFactor).clamp(mergeMin, mergeMax);
    }
    return 10.0; // Default for outline mode
  }

  /// Get vectorization parameters for the given mode
  CenterlineVectorParams paramsFor(double fontSize, {String? actionType}) {
    final useCenterline = shouldUseCenterline(fontSize, actionType: actionType);

    if (useCenterline) {
      return CenterlineVectorParams(
        isCenterline: true,
        epsilon: epsilon,
        resampleSpacing: resample,
        mergeMaxDist: mergeDistanceFor(fontSize),
        smoothPasses: smoothPasses,
      );
    } else {
      return const CenterlineVectorParams(
        isCenterline: false,
        epsilon: 0.8,
        resampleSpacing: 1.0,
        mergeMaxDist: 10.0,
        smoothPasses: 1,
      );
    }
  }

  CenterlineConfig copyWith({
    double? threshold,
    double? epsilon,
    double? resample,
    double? mergeFactor,
    double? mergeMin,
    double? mergeMax,
    int? smoothPasses,
    bool? preferOutlineHeadings,
  }) {
    return CenterlineConfig(
      threshold: threshold ?? this.threshold,
      epsilon: epsilon ?? this.epsilon,
      resample: resample ?? this.resample,
      mergeFactor: mergeFactor ?? this.mergeFactor,
      mergeMin: mergeMin ?? this.mergeMin,
      mergeMax: mergeMax ?? this.mergeMax,
      smoothPasses: smoothPasses ?? this.smoothPasses,
      preferOutlineHeadings: preferOutlineHeadings ?? this.preferOutlineHeadings,
    );
  }
}

/// Vectorization parameters for centerline or outline mode
class CenterlineVectorParams {
  final bool isCenterline;
  final double epsilon;
  final double resampleSpacing;
  final double mergeMaxDist;
  final int smoothPasses;

  const CenterlineVectorParams({
    required this.isCenterline,
    required this.epsilon,
    required this.resampleSpacing,
    required this.mergeMaxDist,
    required this.smoothPasses,
  });
}

/// Combined text rendering configuration
class TextRenderConfig {
  final FontConfig fonts;
  final IndentConfig indent;
  final CenterlineConfig centerline;

  /// Line height multiplier
  final double lineHeight;

  /// Average character width as fraction of font size (for word wrap estimation)
  final double charWidthFactor;

  /// Minimum characters per line
  final int minCharsPerLine;

  const TextRenderConfig({
    this.fonts = const FontConfig(),
    this.indent = const IndentConfig(),
    this.centerline = const CenterlineConfig(),
    this.lineHeight = 1.3,
    this.charWidthFactor = 0.55,
    this.minCharsPerLine = 8,
  });

  /// Default configuration
  static const TextRenderConfig defaultConfig = TextRenderConfig();

  TextRenderConfig copyWith({
    FontConfig? fonts,
    IndentConfig? indent,
    CenterlineConfig? centerline,
    double? lineHeight,
    double? charWidthFactor,
    int? minCharsPerLine,
  }) {
    return TextRenderConfig(
      fonts: fonts ?? this.fonts,
      indent: indent ?? this.indent,
      centerline: centerline ?? this.centerline,
      lineHeight: lineHeight ?? this.lineHeight,
      charWidthFactor: charWidthFactor ?? this.charWidthFactor,
      minCharsPerLine: minCharsPerLine ?? this.minCharsPerLine,
    );
  }
}
