import 'dart:math' as math;
import 'dart:ui' show Offset;
import '../models/drawable_stroke.dart';

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
}
