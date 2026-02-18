import 'dart:ui' show Offset, Rect;

// Native implementation stub - uses opencv_dart if available
// For web, the vectorizer_web.dart is used instead

class Vectorizer {
  static Future<List<List<Offset>>> vectorize({
    required List<int> bytes,
    double worldScale = 1.0,
    String edgeMode = 'Canny',
    int blurK = 5,
    double cannyLo = 50,
    double cannyHi = 160,
    double dogSigma = 1.2,
    double dogK = 1.6,
    double dogThresh = 6.0,
    double epsilon = 1.1187500000000001,
    double resampleSpacing = 1.410714285714286,
    double minPerimeter = 19.839285714285793,
    bool retrExternalOnly = true,
    double angleThresholdDeg = 30,
    int angleWindow = 4,
    int smoothPasses = 3,
    bool mergeParallel = true,
    double mergeMaxDist = 12.0,
    double minStrokeLen = 8.70,
    int minStrokePoints = 6,
  }) async {
    // Native implementation not available for this platform
    // Return empty strokes - web version uses OpenCV.js
    throw UnsupportedError(
      'Native vectorization not supported. Use web build with OpenCV.js.',
    );
  }
}
