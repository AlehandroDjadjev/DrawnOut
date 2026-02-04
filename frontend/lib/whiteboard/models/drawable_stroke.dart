import 'dart:ui';

/// Drawable stroke with rendering data and timing information
class DrawableStroke {
  /// Origin JSON name for grouping/erasing
  final String jsonName;
  
  /// Object placement origin
  final Offset objectOrigin;
  
  /// Object scale factor
  final double objectScale;

  /// Display points (upscaled + wobble + placed)
  final List<Offset> points;
  
  /// Original points (pre-wobble, downsampled, with placement)
  final List<Offset> originalPoints;
  
  /// Total stroke length in pixels
  final double lengthPx;
  
  /// Geometric centroid
  final Offset centroid;
  
  /// Bounding rectangle
  final Rect bounds;
  
  /// Average curvature in degrees
  final double curvatureMetricDeg;

  /// Cumulative geometric length at each point
  final List<double> cumGeomLen;
  
  /// Cumulative draw cost at each point (for timing)
  final List<double> cumDrawCost;
  
  /// Total draw cost
  final double drawCostTotal;

  /// Time to draw this stroke in seconds
  double drawTimeSec;
  
  /// Travel/pause time before this stroke starts
  double travelTimeBeforeSec;
  
  /// Total time weight (travel + draw)
  double timeWeight;

  /// Group ID for clustering
  int groupId;
  
  /// Size of the group this stroke belongs to
  int groupSize;
  
  /// Importance score for prioritization
  double importanceScore;

  DrawableStroke({
    required this.jsonName,
    required this.objectOrigin,
    required this.objectScale,
    required this.points,
    required this.originalPoints,
    required this.lengthPx,
    required this.centroid,
    required this.bounds,
    required this.curvatureMetricDeg,
    required this.cumGeomLen,
    required this.cumDrawCost,
    required this.drawCostTotal,
    required this.drawTimeSec,
    this.travelTimeBeforeSec = 0.0,
    this.timeWeight = 0.0,
    this.groupId = -1,
    this.groupSize = 1,
    this.importanceScore = 0.0,
  });
}
