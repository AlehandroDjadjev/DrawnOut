/// Whiteboard engine module.
///
/// Provides core data structures, painters, layout system, widgets,
/// and services for the animated whiteboard rendering system.
///
/// ## Usage
///
/// ```dart
/// import 'package:whiteboard_demo/whiteboard/whiteboard.dart';
///
/// // Create a stroke plan
/// final plan = StrokePlan(strokes);
///
/// // Use SketchPlayer widget to animate
/// SketchPlayer(
///   plan: plan,
///   totalSeconds: 5.0,
/// )
///
/// // Use services for processing
/// final strokeService = StrokeService();
/// final filtered = strokeService.filterStrokes(strokes);
/// ```
library;

// Core data structures
export 'core/core.dart';

// Custom painters
export 'painters/painters.dart';

// Layout system
export 'layout/layout.dart';

// Widgets
export 'widgets/widgets.dart';

// Services
export 'services/services.dart';
