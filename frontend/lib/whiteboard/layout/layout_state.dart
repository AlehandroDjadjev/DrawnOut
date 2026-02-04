import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Bounding box with intersection detection
class BBox {
  final double x;
  final double y;
  final double w;
  final double h;

  const BBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  double get x2 => x + w;
  double get y2 => y + h;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  /// Check if this box intersects with another
  bool intersects(BBox other) {
    return !(x2 <= other.x || other.x2 <= x || y2 <= other.y || other.y2 <= y);
  }

  /// Check if a point is inside this box
  bool contains(Offset point) {
    return point.dx >= x && point.dx <= x2 && point.dy >= y && point.dy <= y2;
  }

  @override
  String toString() => 'BBox($x, $y, $w, $h)';
}

/// Represents a placed content block on the whiteboard
class DrawnBlock {
  final String id;
  final String type;
  final BBox bbox;
  final Map<String, dynamic> meta;

  const DrawnBlock({
    required this.id,
    required this.type,
    required this.bbox,
    this.meta = const {},
  });

  @override
  String toString() => 'DrawnBlock($id, $type, $bbox)';
}

/// Page configuration
class PageConfig {
  final double width;
  final double height;
  final double left;
  final double right;
  final double top;
  final double bottom;

  const PageConfig({
    this.width = 1600.0,
    this.height = 1000.0,
    this.left = 48.0,
    this.right = 48.0,
    this.top = 48.0,
    this.bottom = 48.0,
  });

  double get contentWidth => width - left - right;
  double get contentHeight => height - top - bottom;

  static const PageConfig defaultConfig = PageConfig();
}

/// Multi-column configuration
class ColumnsConfig {
  final int count;
  final double gutter;

  const ColumnsConfig({
    this.count = 1,
    this.gutter = 48.0,
  });

  static const ColumnsConfig single = ColumnsConfig(count: 1);
  static const ColumnsConfig dual = ColumnsConfig(count: 2);
}

/// Complete layout configuration
class LayoutConfig {
  final PageConfig page;
  final ColumnsConfig? columns;
  final double lineHeight;
  final double gutterY;

  const LayoutConfig({
    this.page = const PageConfig(),
    this.columns,
    this.lineHeight = 1.3,
    this.gutterY = 12.0,
  });

  static const LayoutConfig defaultConfig = LayoutConfig();
}

/// Mutable layout state tracking cursor position and placed blocks
class LayoutState {
  /// Current vertical cursor position
  double cursorY;

  /// Current column index (0-based)
  int columnIndex;

  /// List of all placed blocks for collision detection
  final List<DrawnBlock> blocks;

  /// Section/page counter
  int sectionCount;

  /// The layout configuration
  final LayoutConfig config;

  LayoutState({
    required this.cursorY,
    required this.columnIndex,
    required this.blocks,
    required this.sectionCount,
    required this.config,
  });

  /// Create initial layout state
  factory LayoutState.initial({LayoutConfig? config}) {
    final cfg = config ?? LayoutConfig.defaultConfig;
    return LayoutState(
      cursorY: cfg.page.top,
      columnIndex: 0,
      blocks: [],
      sectionCount: 0,
      config: cfg,
    );
  }

  /// Calculate column offset X based on current column index
  double columnOffsetX() {
    if (config.columns == null || config.columns!.count <= 1) return 0.0;
    final colW = columnWidth();
    return columnIndex * (colW + config.columns!.gutter);
  }

  /// Calculate column width
  double columnWidth() {
    final pageW = config.page.contentWidth;
    if (config.columns == null || config.columns!.count <= 1) return pageW;
    final n = config.columns!.count;
    final gutter = config.columns!.gutter;
    return (pageW - (n - 1) * gutter) / n;
  }

  /// Get the X position for content start in current column
  double get contentX => config.page.left + columnOffsetX();

  /// Check if we need to advance to next column
  bool shouldAdvanceColumn(double requiredHeight) {
    final pageBottom = config.page.height - config.page.bottom;
    final remaining = pageBottom - cursorY;
    
    if (remaining < requiredHeight &&
        config.columns != null &&
        columnIndex < (config.columns!.count - 1)) {
      return true;
    }
    return false;
  }

  /// Advance to next column if available
  bool advanceColumn() {
    if (config.columns == null) return false;
    if (columnIndex >= (config.columns!.count - 1)) return false;

    columnIndex++;
    cursorY = config.page.top;
    return true;
  }

  /// Reset layout state to initial
  void reset() {
    cursorY = config.page.top;
    columnIndex = 0;
    blocks.clear();
    sectionCount = 0;
  }

  /// Create a copy of this state
  LayoutState copy() {
    return LayoutState(
      cursorY: cursorY,
      columnIndex: columnIndex,
      blocks: List.from(blocks),
      sectionCount: sectionCount,
      config: config,
    );
  }
}

/// Service for layout calculations and collision detection
class LayoutService {
  /// Find the next Y position that doesn't collide with existing blocks
  ///
  /// [state] - Current layout state
  /// [x] - X position of the new content
  /// [height] - Height of the new content
  /// [startY] - Starting Y position to check from
  /// [margin] - Additional margin to add after collisions
  static double nextNonCollidingY(
    LayoutState state,
    double x,
    double height,
    double startY, {
    double margin = 12.0,
    BBox? ignoreBlock,
  }) {
    double y = startY;
    final w = state.columnWidth();
    final x2 = x + w;
    final maxIterations = 100;
    int iterations = 0;

    bool hasCollision = true;
    while (hasCollision && iterations < maxIterations) {
      hasCollision = false;
      final testBox = BBox(x: x, y: y, w: w, h: height);

      for (final block in state.blocks) {
        if (ignoreBlock != null && _bboxEquals(block.bbox, ignoreBlock)) {
          continue;
        }

        if (testBox.intersects(block.bbox)) {
          y = block.bbox.y2 + margin;
          hasCollision = true;
          break;
        }
      }
      iterations++;
    }

    return y;
  }

  static bool _bboxEquals(BBox a, BBox b) {
    return a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h;
  }

  /// Calculate optimal placement for an image
  ///
  /// Returns the placement coordinates and whether column was advanced
  static ImagePlacementResult calculateImagePlacement(
    LayoutState state, {
    required double imageWidth,
    required double imageHeight,
    double? explicitX,
    double? explicitY,
    double? explicitWidth,
    double? explicitHeight,
    double? scale,
    double maxWidthFraction = 0.4,
  }) {
    final cfg = state.config;
    double contentX0 = cfg.page.left + state.columnOffsetX();
    double cw = state.columnWidth();

    // Target dimensions
    double targetW, targetH;
    double x, y;
    bool columnAdvanced = false;

    final hasExplicit = explicitX != null && explicitY != null;

    if (hasExplicit) {
      // Use explicit placement
      x = explicitX;
      y = explicitY;
      targetW = explicitWidth ?? (cw * maxWidthFraction);
      targetH = explicitHeight ??
          (targetW * (imageHeight / math.max(1, imageWidth)));

      if (scale != null && scale > 0) {
        targetW *= scale;
        targetH *= scale;
      }
    } else {
      // Auto-placement
      double maxW = cw * maxWidthFraction;

      // Center horizontally in column
      x = contentX0 + (cw - maxW) / 2.0;
      y = state.cursorY;

      // Check for column overflow
      final pageBottom = cfg.page.height - cfg.page.bottom;
      if ((pageBottom - y) < 100 && state.advanceColumn()) {
        columnAdvanced = true;
        contentX0 = cfg.page.left + state.columnOffsetX();
        cw = state.columnWidth();
        maxW = cw * maxWidthFraction;
        x = contentX0 + (cw - maxW) / 2.0;
        y = cfg.page.top;
      }

      // Scale to fit available space
      final remainH = (cfg.page.height - cfg.page.bottom) - y - cfg.gutterY;
      final scaleW = imageWidth == 0 ? 1.0 : (maxW / imageWidth);
      final scaleH = imageHeight == 0 ? scaleW : math.max(0.1, remainH / imageHeight);
      final effScale = math.min(scaleW, scaleH);

      targetW = imageWidth * effScale;
      targetH = imageHeight * effScale;

      // Avoid overlaps
      y = nextNonCollidingY(state, x, targetH, y);
    }

    return ImagePlacementResult(
      x: x,
      y: y,
      width: targetW,
      height: targetH,
      columnAdvanced: columnAdvanced,
    );
  }
}

/// Result of image placement calculation
class ImagePlacementResult {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool columnAdvanced;

  const ImagePlacementResult({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.columnAdvanced = false,
  });

  BBox get bbox => BBox(x: x, y: y, w: width, h: height);

  /// Convert to world coordinates (centered origin)
  Offset toWorldCenter(PageConfig page) {
    return Offset(
      x - (page.width / 2) + (width / 2),
      y - (page.height / 2) + (height / 2),
    );
  }
}
