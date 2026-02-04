import 'dart:typed_data';
import 'layout_config.dart';

/// Bounding box for collision detection.
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

  double get right => x + w;
  double get bottom => y + h;

  /// Check if this box intersects with another.
  bool intersects(BBox other) {
    return !(other.x >= right ||
        other.right <= x ||
        other.y >= bottom ||
        other.bottom <= y);
  }
}

/// A drawn block on the whiteboard with position and metadata.
class DrawnBlock {
  final String id;
  final String type;
  final BBox bbox;
  final Map<String, dynamic>? meta;

  DrawnBlock({
    required this.id,
    required this.type,
    required this.bbox,
    this.meta,
  });
}

/// Rendered text line with pixel data.
class RenderedLine {
  final Uint8List bytes;
  final double w;
  final double h;

  RenderedLine({
    required this.bytes,
    required this.w,
    required this.h,
  });
}

/// Mutable layout state tracking cursor position and drawn blocks.
class LayoutState {
  final LayoutConfig config;
  double cursorY;
  int columnIndex;
  final List<DrawnBlock> blocks;
  int sectionCount;

  LayoutState({
    required this.config,
    required this.cursorY,
    required this.columnIndex,
    required this.blocks,
    required this.sectionCount,
  });

  /// Create default layout state for a given page size.
  factory LayoutState.defaultConfig(double pageW, double pageH) {
    final cfg = LayoutConfig.defaultConfig(pageW, pageH);
    return LayoutState(
      config: cfg,
      cursorY: cfg.page.top,
      columnIndex: 0,
      blocks: <DrawnBlock>[],
      sectionCount: 0,
    );
  }

  /// Get the X offset for the current column.
  double columnOffsetX() {
    if (config.columns == null) return 0.0;
    final cw = columnWidth();
    return columnIndex * cw + columnIndex * config.columns!.gutter;
  }

  /// Calculate remaining column space.
  double columnResidual() {
    if (config.columns == null) return 0.0;
    final total = (config.columns!.count - 1) * config.columns!.gutter +
        (config.columns!.count - 1) * columnWidth();
    final used =
        columnIndex * config.columns!.gutter + columnIndex * columnWidth();
    return total - used;
  }

  /// Get the width of a single column.
  double columnWidth() {
    if (config.columns == null) {
      return config.page.width - config.page.left - config.page.right;
    }
    final usable = config.page.width -
        config.page.left -
        config.page.right -
        (config.columns!.count - 1) * config.columns!.gutter;
    return usable / config.columns!.count;
  }

  /// Reset cursor to top of current column.
  void resetCursor() {
    cursorY = config.page.top;
  }

  /// Move to next column, resetting cursor.
  void nextColumn() {
    if (config.columns != null && columnIndex < config.columns!.count - 1) {
      columnIndex++;
      resetCursor();
    }
  }

  /// Clear all blocks and reset layout.
  void clear() {
    blocks.clear();
    columnIndex = 0;
    cursorY = config.page.top;
    sectionCount = 0;
  }
}
