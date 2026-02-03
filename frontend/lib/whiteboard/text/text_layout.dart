import 'dart:math' as math;
import 'text_config.dart';

/// Result of laying out text for rendering
class TextLayoutResult {
  /// The wrapped lines of text
  final List<String> lines;

  /// Font size used for rendering
  final double fontSize;

  /// Indentation applied
  final double indent;

  /// Total height of the text block
  final double height;

  /// Maximum width available for text
  final double maxWidth;

  /// The original text before wrapping
  final String originalText;

  /// The action type that produced this layout
  final String actionType;

  const TextLayoutResult({
    required this.lines,
    required this.fontSize,
    required this.indent,
    required this.height,
    required this.maxWidth,
    required this.originalText,
    required this.actionType,
  });

  /// Number of lines after wrapping
  int get lineCount => lines.length;

  /// Whether text was wrapped (more than one line)
  bool get wasWrapped => lines.length > 1;
}

/// Service for text layout calculations (word wrapping, sizing)
class TextLayoutService {
  final TextRenderConfig config;

  TextLayoutService({TextRenderConfig? config})
      : config = config ?? TextRenderConfig.defaultConfig;

  /// Calculate font size for an action type
  ///
  /// [type] - The action type (heading, bullet, formula, etc.)
  /// [styleOverride] - Optional style map with fontSize
  /// [fontScale] - Multiplier for the base font size
  double calculateFontSize(
    String type, {
    Map<String, dynamic>? styleOverride,
    double fontScale = 1.0,
  }) {
    double size = config.fonts.forType(type, styleOverride: styleOverride);
    size *= fontScale;
    return config.fonts.applyMinimum(size);
  }

  /// Calculate indentation for an action type and level
  double calculateIndent(String type, int level) {
    return config.indent.forType(type, level);
  }

  /// Wrap text to fit within a maximum width
  ///
  /// Uses a character-width heuristic for fast estimation.
  /// [text] - The text to wrap
  /// [fontSize] - Font size for character width estimation
  /// [maxWidth] - Maximum available width in pixels
  List<String> wrapText(String text, double fontSize, double maxWidth) {
    // Estimate average character width
    final avgCharWidth = fontSize * config.charWidthFactor;
    final maxChars = math.max(
      config.minCharsPerLine,
      (maxWidth / avgCharWidth).floor(),
    );

    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    String currentLine = '';
    int currentLength = 0;

    for (final word in words) {
      if (word.isEmpty) continue;

      final wordLength = word.length;
      final spaceNeeded = currentLine.isEmpty ? 0 : 1;

      if (currentLength + spaceNeeded + wordLength > maxChars && currentLine.isNotEmpty) {
        // Start new line
        lines.add(currentLine);
        currentLine = word;
        currentLength = wordLength;
      } else {
        // Add to current line
        if (currentLine.isNotEmpty) {
          currentLine += ' ';
          currentLength += 1;
        }
        currentLine += word;
        currentLength += wordLength;
      }
    }

    // Add remaining text
    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines.isEmpty ? [''] : lines;
  }

  /// Calculate the total height of wrapped text
  double calculateHeight(int lineCount, double fontSize) {
    return (lineCount * fontSize * config.lineHeight).ceilToDouble();
  }

  /// Layout text for a drawing action
  ///
  /// This combines font selection, indentation, and word wrapping.
  TextLayoutResult layoutText({
    required String text,
    required String type,
    required double contentWidth,
    int level = 1,
    Map<String, dynamic>? style,
    double fontScale = 1.0,
  }) {
    // Calculate font size
    final fontSize = calculateFontSize(type, styleOverride: style, fontScale: fontScale);

    // Calculate indentation
    final indent = calculateIndent(type, level);

    // Calculate available width for text
    final maxWidth = (contentWidth - indent).clamp(80.0, contentWidth);

    // Wrap text
    final lines = wrapText(text, fontSize, maxWidth);

    // Calculate height
    final height = calculateHeight(lines.length, fontSize);

    return TextLayoutResult(
      lines: lines,
      fontSize: fontSize,
      indent: indent,
      height: height,
      maxWidth: maxWidth,
      originalText: text,
      actionType: type,
    );
  }

  /// Get centerline parameters for the current font size
  CenterlineVectorParams getCenterlineParams(double fontSize, {String? actionType}) {
    return config.centerline.paramsFor(fontSize, actionType: actionType);
  }

  /// Check if outline mode should be preferred for this text
  bool shouldPreferOutline(double fontSize, {String? actionType}) {
    return !config.centerline.shouldUseCenterline(fontSize, actionType: actionType);
  }
}

/// Estimates character width for various text styles
class CharWidthEstimator {
  /// Estimate width of a string in pixels
  ///
  /// This is a rough estimate based on character counts and typical widths.
  static double estimateWidth(String text, double fontSize, {double factor = 0.55}) {
    // Count different character types
    int narrowChars = 0; // i, l, j, f, t, 1, punctuation
    int wideChars = 0;   // m, w, M, W
    int normalChars = 0; // everything else

    for (final char in text.runes) {
      final c = String.fromCharCode(char);
      if ('iljft1.,;:\'"!|'.contains(c)) {
        narrowChars++;
      } else if ('mwMW'.contains(c)) {
        wideChars++;
      } else {
        normalChars++;
      }
    }

    // Weighted sum
    final weightedChars = narrowChars * 0.4 + wideChars * 1.3 + normalChars;
    return weightedChars * fontSize * factor;
  }

  /// Estimate characters that fit in a width
  static int estimateCharsInWidth(double width, double fontSize, {double factor = 0.55}) {
    final avgCharWidth = fontSize * factor;
    return math.max(1, (width / avgCharWidth).floor());
  }
}
