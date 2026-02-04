/// Configuration classes for whiteboard layout.
///
/// These define page dimensions, margins, fonts, indentation, and columns.

/// Page dimensions and margins.
///
/// Named `PageConfig` to avoid conflict with Flutter's `Page` class.
class PageConfig {
  final double width;
  final double height;
  final double top;
  final double right;
  final double bottom;
  final double left;

  const PageConfig({
    required this.width,
    required this.height,
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  /// Usable content width (excluding margins).
  double get contentWidth => width - left - right;

  /// Usable content height (excluding margins).
  double get contentHeight => height - top - bottom;
}

/// Indentation levels for different content types.
class Indent {
  final double level1;
  final double level2;
  final double level3;

  const Indent({
    required this.level1,
    required this.level2,
    required this.level3,
  });

  /// Get indentation for a specific level (1-based).
  double forLevel(int level) {
    if (level <= 1) return level1;
    if (level == 2) return level2;
    return level3;
  }
}

/// Multi-column layout configuration.
class Columns {
  final int count;
  final double gutter;

  const Columns({
    required this.count,
    required this.gutter,
  });
}

/// Font sizes for different text types.
class Fonts {
  final double heading;
  final double body;
  final double tiny;

  const Fonts({
    required this.heading,
    required this.body,
    required this.tiny,
  });
}

/// Complete layout configuration.
class LayoutConfig {
  final PageConfig page;
  final double lineHeight;
  final double gutterY;
  final Indent indent;
  final Columns? columns;
  final Fonts fonts;

  const LayoutConfig({
    required this.page,
    required this.lineHeight,
    required this.gutterY,
    required this.indent,
    required this.columns,
    required this.fonts,
  });

  /// Create default configuration for a given page size.
  factory LayoutConfig.defaultConfig(double pageW, double pageH) {
    return LayoutConfig(
      page: PageConfig(
        width: pageW,
        height: pageH,
        top: 60,
        right: 64,
        bottom: 60,
        left: 64,
      ),
      lineHeight: 1.25,
      gutterY: 14,
      indent: const Indent(level1: 32, level2: 64, level3: 96),
      columns: null,
      fonts: const Fonts(heading: 30, body: 22, tiny: 18),
    );
  }
}
