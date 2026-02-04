/// Layout management for whiteboard content
///
/// This module provides:
/// - [LayoutState] - Mutable state tracking cursor position and placed blocks
/// - [LayoutConfig] - Configuration for page size, margins, columns
/// - [LayoutService] - Service for collision detection and placement calculations
/// - [BBox], [DrawnBlock] - Data structures for tracking placed content
library;

export 'layout_state.dart';
