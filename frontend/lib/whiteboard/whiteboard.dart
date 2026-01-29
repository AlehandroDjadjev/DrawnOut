/// Whiteboard module - unified drawing engine
///
/// This module provides all components for the whiteboard functionality:
/// - Models for stroke data and timelines
/// - Painters for canvas rendering
/// - Services for timing, backend sync, and stroke building
/// - Controllers for state management and playback
library;

// Models
export 'models/stroke_types.dart';
export 'models/drawable_stroke.dart';
export 'models/timeline.dart';

// Painters
export 'painters/whiteboard_painter.dart';

// Services
export 'services/stroke_timing_service.dart';
export 'services/stroke_builder_service.dart';
export 'services/whiteboard_backend_service.dart';
export 'services/timeline_api_service.dart';
export 'services/lesson_api_service.dart';

// Controllers
export 'controllers/whiteboard_controller.dart';
export 'controllers/timeline_playback_controller.dart';
