/// Whiteboard module - unified drawing engine
///
/// This module provides all components for the whiteboard functionality:
/// - Core data structures (StrokePlan, VectorObject, PlacedImage)
/// - Models for stroke data and timelines
/// - Painters for canvas rendering (with multi-pass jitter)
/// - Services for timing, backend sync, and stroke building
/// - Text rendering utilities (font config, word wrap, centerline mode)
/// - Layout management (collision detection, multi-column support)
/// - Image handling (sketch_image pipeline, vectorization)
/// - Controllers for state management and playback
library;

// Core data structures (extracted from whiteboard_demo)
export 'core/stroke_plan.dart';
export 'core/vector_object.dart';
export 'core/placed_image.dart';

// Models
export 'models/stroke_types.dart';
export 'models/drawable_stroke.dart';
export 'models/timeline.dart';

// Painters
export 'painters/whiteboard_painter.dart';
export 'painters/sketch_painter.dart';
export 'painters/committed_painter.dart';

// Services
export 'services/stroke_timing_service.dart';
export 'services/stroke_builder_service.dart';
export 'services/whiteboard_backend_service.dart';
export 'services/timeline_api_service.dart';
export 'services/lesson_api_service.dart';

// Text rendering utilities
export 'text/text_config.dart';
export 'text/text_layout.dart';

// Layout management
export 'layout/layout_state.dart';

// Image handling
export 'image/image_sketch_service.dart';

// Controllers
export 'controllers/whiteboard_controller.dart';
export 'controllers/timeline_playback_controller.dart';
