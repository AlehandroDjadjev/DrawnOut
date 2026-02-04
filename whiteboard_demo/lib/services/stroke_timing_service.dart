import 'dart:math' as math;
import 'dart:ui' show Offset;
import '../models/drawable_stroke.dart';
import '../models/timeline.dart';

/// Result of analyzing drawing actions for timing
class DrawingTimingAnalysis {
  /// Total character count of text actions
  final int totalCharacters;

  /// Number of text-based actions
  final int textActionCount;

  /// Number of image actions
  final int imageActionCount;

  /// Whether this is detected as a dictation segment
  final bool isDictationSegment;

  /// Calculated draw duration in seconds
  final double drawDurationSeconds;

  /// Extra time added for images (seconds)
  final double imageTimeSeconds;

  /// Audio duration of the segment (if available)
  final double? audioDurationSeconds;

  const DrawingTimingAnalysis({
    required this.totalCharacters,
    required this.textActionCount,
    required this.imageActionCount,
    required this.isDictationSegment,
    required this.drawDurationSeconds,
    required this.imageTimeSeconds,
    this.audioDurationSeconds,
  });

  @override
  String toString() => 'DrawingTimingAnalysis('
      'chars: $totalCharacters, '
      'text: $textActionCount, '
      'images: $imageActionCount, '
      'dictation: $isDictationSegment, '
      'duration: ${drawDurationSeconds.toStringAsFixed(1)}s)';
}

/// Tracks when animations are expected to finish
class AnimationEndTracker {
  DateTime? _textAnimationEnd;
  DateTime? _imageAnimationEnd;

  /// When the current text animation is expected to finish
  DateTime? get textAnimationEnd => _textAnimationEnd;

  /// When the current image/diagram animation is expected to finish
  DateTime? get imageAnimationEnd => _imageAnimationEnd;

  /// Set when text animation should end
  void setTextEnd(Duration duration) {
    _textAnimationEnd = DateTime.now().add(duration);
  }

  /// Set when image animation should end
  void setImageEnd(Duration duration) {
    _imageAnimationEnd = DateTime.now().add(duration);
  }

  /// Clear the text animation end
  void clearTextEnd() => _textAnimationEnd = null;

  /// Clear the image animation end
  void clearImageEnd() => _imageAnimationEnd = null;

  /// Clear all animation ends
  void clearAll() {
    _textAnimationEnd = null;
    _imageAnimationEnd = null;
  }

  /// Check if all animations are complete and we can advance to next segment
  bool canAdvanceSegment() {
    final now = DateTime.now();
    final textDone = _textAnimationEnd == null || !_textAnimationEnd!.isAfter(now);
    final imageDone = _imageAnimationEnd == null || !_imageAnimationEnd!.isAfter(now);
    return textDone && imageDone;
  }

  /// Get remaining time until all animations complete (in milliseconds)
  int remainingMilliseconds() {
    final now = DateTime.now();
    int remaining = 0;

    if (_textAnimationEnd != null && _textAnimationEnd!.isAfter(now)) {
      remaining = math.max(remaining, _textAnimationEnd!.difference(now).inMilliseconds);
    }
    if (_imageAnimationEnd != null && _imageAnimationEnd!.isAfter(now)) {
      remaining = math.max(remaining, _imageAnimationEnd!.difference(now).inMilliseconds);
    }

    return remaining;
  }

  /// Wait until the text animation end is reached (or timeout)
  Future<void> waitForTextEnd({int maxWaitMs = 1000}) async {
    int waited = 0;
    const checkInterval = Duration(milliseconds: 50);

    while (_textAnimationEnd == null && waited < maxWaitMs) {
      await Future.delayed(checkInterval);
      waited += 50;
    }

    if (_textAnimationEnd != null) {
      final now = DateTime.now();
      if (_textAnimationEnd!.isAfter(now)) {
        await Future.delayed(_textAnimationEnd!.difference(now));
      }
    }
  }
}

/// Configuration for stroke timing calculations
class StrokeTimingConfig {
  // Stroke draw timing (seconds)
  double minStrokeTimeSec;
  double maxStrokeTimeSec;
  double lengthTimePerKPxSec;
  double curvatureExtraMaxSec;

  // Curvature profile
  double curvatureProfileFactor;
  double curvatureAngleScale;

  // Travel timing between strokes
  double baseTravelTimeSec;
  double travelTimePerKPxSec;
  double minTravelTimeSec;
  double maxTravelTimeSec;

  // Global
  double globalSpeedMultiplier;

  // Text-specific
  double textStrokeBaseTimeSec;
  double textStrokeCurveExtraFrac;

  StrokeTimingConfig({
    this.minStrokeTimeSec = 0.18,
    this.maxStrokeTimeSec = 0.32,
    this.lengthTimePerKPxSec = 0.08,
    this.curvatureExtraMaxSec = 0.08,
    this.curvatureProfileFactor = 1.5,
    this.curvatureAngleScale = 80.0,
    this.baseTravelTimeSec = 0.15,
    this.travelTimePerKPxSec = 0.12,
    this.minTravelTimeSec = 0.15,
    this.maxTravelTimeSec = 0.35,
    this.globalSpeedMultiplier = 1.0,
    this.textStrokeBaseTimeSec = 0.035,
    this.textStrokeCurveExtraFrac = 0.25,
  });

  /// Create a copy with optional overrides
  StrokeTimingConfig copyWith({
    double? minStrokeTimeSec,
    double? maxStrokeTimeSec,
    double? lengthTimePerKPxSec,
    double? curvatureExtraMaxSec,
    double? curvatureProfileFactor,
    double? curvatureAngleScale,
    double? baseTravelTimeSec,
    double? travelTimePerKPxSec,
    double? minTravelTimeSec,
    double? maxTravelTimeSec,
    double? globalSpeedMultiplier,
    double? textStrokeBaseTimeSec,
    double? textStrokeCurveExtraFrac,
  }) {
    return StrokeTimingConfig(
      minStrokeTimeSec: minStrokeTimeSec ?? this.minStrokeTimeSec,
      maxStrokeTimeSec: maxStrokeTimeSec ?? this.maxStrokeTimeSec,
      lengthTimePerKPxSec: lengthTimePerKPxSec ?? this.lengthTimePerKPxSec,
      curvatureExtraMaxSec: curvatureExtraMaxSec ?? this.curvatureExtraMaxSec,
      curvatureProfileFactor: curvatureProfileFactor ?? this.curvatureProfileFactor,
      curvatureAngleScale: curvatureAngleScale ?? this.curvatureAngleScale,
      baseTravelTimeSec: baseTravelTimeSec ?? this.baseTravelTimeSec,
      travelTimePerKPxSec: travelTimePerKPxSec ?? this.travelTimePerKPxSec,
      minTravelTimeSec: minTravelTimeSec ?? this.minTravelTimeSec,
      maxTravelTimeSec: maxTravelTimeSec ?? this.maxTravelTimeSec,
      globalSpeedMultiplier: globalSpeedMultiplier ?? this.globalSpeedMultiplier,
      textStrokeBaseTimeSec: textStrokeBaseTimeSec ?? this.textStrokeBaseTimeSec,
      textStrokeCurveExtraFrac: textStrokeCurveExtraFrac ?? this.textStrokeCurveExtraFrac,
    );
  }
}

/// Service for computing stroke animation timing
class StrokeTimingService {
  StrokeTimingConfig config;

  StrokeTimingService({StrokeTimingConfig? config})
      : config = config ?? StrokeTimingConfig();

  /// Compute timing for a list of strokes
  /// Returns total animation duration in seconds
  double computeTiming(List<DrawableStroke> strokes, {bool isText = false}) {
    if (strokes.isEmpty) return 0.0;

    if (isText) {
      _computeTextTiming(strokes);
    } else {
      _computeObjectTiming(strokes);
    }

    final totalSeconds = strokes.fold<double>(0.0, (sum, d) => sum + d.timeWeight);
    return totalSeconds > 0 ? totalSeconds / config.globalSpeedMultiplier : 0.0;
  }

  void _computeTextTiming(List<DrawableStroke> strokes) {
    for (final s in strokes) {
      final curvature = s.curvatureMetricDeg;
      final curvNorm = (curvature / 70.0).clamp(0.0, 1.0);
      final base = config.textStrokeBaseTimeSec;
      final extra = base * config.textStrokeCurveExtraFrac * curvNorm;
      s.drawTimeSec = base + extra;
      s.travelTimeBeforeSec = 0.0;
      s.timeWeight = s.drawTimeSec;
    }
  }

  void _computeObjectTiming(List<DrawableStroke> strokes) {
    // Compute draw times based on length and curvature
    for (final s in strokes) {
      final length = s.lengthPx;
      final curvature = s.curvatureMetricDeg;

      final lengthK = length / 1000.0;
      final curvNorm = (curvature / 70.0).clamp(0.0, 1.0);

      final rawTime = config.minStrokeTimeSec +
          lengthK * config.lengthTimePerKPxSec +
          curvNorm * config.curvatureExtraMaxSec;

      s.drawTimeSec = rawTime.clamp(config.minStrokeTimeSec, config.maxStrokeTimeSec);
    }

    // Compute travel times between strokes
    DrawableStroke? prev;
    for (final s in strokes) {
      double travel = 0.0;

      if (prev != null) {
        final lastP = prev.points.last;
        final firstP = s.points.first;
        final dist = (firstP - lastP).distance;
        final distK = dist / 1000.0;

        final rawTravel = config.baseTravelTimeSec + distK * config.travelTimePerKPxSec;
        travel = rawTravel.clamp(config.minTravelTimeSec, config.maxTravelTimeSec);
      }

      s.travelTimeBeforeSec = travel;
      s.timeWeight = s.travelTimeBeforeSec + s.drawTimeSec;
      prev = s;
    }
  }

  /// Estimate curvature metric in degrees for a set of points
  static double estimateCurvatureDeg(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double sumAng = 0.0;
    int cnt = 0;
    for (int i = 1; i < pts.length - 1; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final c = pts[i + 1];
      final v1 = b - a;
      final v2 = c - b;
      final len1 = v1.distance;
      final len2 = v2.distance;
      if (len1 < 1e-3 || len2 < 1e-3) continue;
      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (len1 * len2);
      final clamped = dot.clamp(-1.0, 1.0);
      final ang = math.acos(clamped) * 180.0 / math.pi;
      sumAng += ang.abs();
      cnt++;
    }
    if (cnt == 0) return 0.0;
    return sumAng / cnt;
  }

  // ==========================================================================
  // DICTATION DETECTION & TIMELINE-AWARE TIMING
  // ==========================================================================

  /// Analyze drawing actions and determine optimal timing
  ///
  /// This implements the dictation detection logic:
  /// - Short text (<50 chars) with long audio (>5s) = dictation mode
  /// - Dictation mode uses 85% of audio duration for slow, deliberate drawing
  /// - Non-dictation uses character count to estimate duration
  DrawingTimingAnalysis analyzeDrawingActions(
    List<DrawingAction> actions, {
    TimelineSegment? segment,
    double secondsPerImage = 3.0,
  }) {
    // Separate text and image actions
    final textActions = actions.where((a) => !a.isSketchImage).toList();
    final imageActions = actions.where((a) => a.isSketchImage).toList();

    // Calculate total characters from text actions
    final totalChars = textActions.fold<int>(0, (sum, a) => sum + a.text.length);

    // Calculate image time
    final imageTime = imageActions.length * secondsPerImage;

    // Check for dictation segment
    final audioDuration = segment?.actualAudioDuration ?? 0.0;
    final isDictation = segment != null &&
        audioDuration > 5.0 &&
        totalChars < 50;

    // Calculate draw duration based on detection
    double drawDuration;
    if (isDictation) {
      // DICTATION MODE: Use 85% of audio duration, clamped to reasonable range
      drawDuration = (audioDuration * 0.85).clamp(6.0, 25.0);
    } else {
      // STANDARD MODE: Use character count heuristics
      drawDuration = _characterCountToDuration(totalChars);
    }

    // Add image time to total
    drawDuration += imageTime;

    return DrawingTimingAnalysis(
      totalCharacters: totalChars,
      textActionCount: textActions.length,
      imageActionCount: imageActions.length,
      isDictationSegment: isDictation,
      drawDurationSeconds: drawDuration,
      imageTimeSeconds: imageTime,
      audioDurationSeconds: segment?.actualAudioDuration,
    );
  }

  /// Convert character count to drawing duration using heuristics
  ///
  /// This matches the whiteboard_demo logic:
  /// - < 10 chars: 5s (even short words take time)
  /// - < 20 chars: 7s (medium text)
  /// - < 40 chars: 10s (formulas)
  /// - < 80 chars: 14s (lists)
  /// - >= 80 chars: 18s (very long)
  double _characterCountToDuration(int charCount) {
    if (charCount < 10) return 5.0;
    if (charCount < 20) return 7.0;
    if (charCount < 40) return 10.0;
    if (charCount < 80) return 14.0;
    return 18.0;
  }

  /// Calculate optimal duration for a set of actions with segment context
  ///
  /// Convenience method that returns just the duration.
  double calculateDuration(
    List<DrawingAction> actions, {
    TimelineSegment? segment,
    double secondsPerImage = 3.0,
    double? minDuration,
    double? maxDuration,
  }) {
    final analysis = analyzeDrawingActions(
      actions,
      segment: segment,
      secondsPerImage: secondsPerImage,
    );

    double duration = analysis.drawDurationSeconds;

    // Apply optional bounds
    if (minDuration != null) duration = math.max(duration, minDuration);
    if (maxDuration != null) duration = math.min(duration, maxDuration);

    return duration;
  }

  /// Check if actions represent a dictation segment
  ///
  /// Dictation segments are detected when:
  /// - Audio duration > 5 seconds
  /// - Total text content < 50 characters
  ///
  /// This indicates the tutor is speaking slowly while drawing,
  /// such as when dictating "a squared plus b squared equals c squared"
  /// while writing "a² + b² = c²".
  bool isDictationSegment(
    List<DrawingAction> actions,
    TimelineSegment? segment,
  ) {
    if (segment == null) return false;
    final audioDuration = segment.actualAudioDuration;
    if (audioDuration <= 5.0) return false;

    final totalChars = actions
        .where((a) => !a.isSketchImage)
        .fold<int>(0, (sum, a) => sum + a.text.length);

    return totalChars < 50;
  }

  /// Get the dictation pace multiplier
  ///
  /// Returns the fraction of audio duration to use for drawing.
  /// Default is 0.85 (85% of audio duration).
  static const double dictationPaceMultiplier = 0.85;

  /// Minimum duration for dictation mode
  static const double dictationMinDuration = 6.0;

  /// Maximum duration for dictation mode
  static const double dictationMaxDuration = 25.0;
}
