import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../layout/layout_state.dart';

/// Configuration for centerline text rendering mode.
///
/// Centerline mode produces thinner, cleaner strokes for small text.
class CenterlineConfig {
  /// Font size threshold below which centerline mode is used
  final double threshold;

  /// Epsilon for stroke simplification (lower = tighter)
  final double epsilon;

  /// Resample spacing (lower = denser sampling)
  final double resample;

  /// Merge factor for nearby strokes (multiplied by font size)
  final double mergeFactor;

  /// Minimum merge distance
  final double mergeMin;

  /// Maximum merge distance
  final double mergeMax;

  /// Number of smoothing passes
  final int smoothPasses;

  const CenterlineConfig({
    this.threshold = 60.0,
    this.epsilon = 0.6,
    this.resample = 0.8,
    this.mergeFactor = 0.9,
    this.mergeMin = 12.0,
    this.mergeMax = 36.0,
    this.smoothPasses = 3,
  });

  /// Calculate merge distance for a given font size.
  double mergeDistanceFor(double fontSize) {
    return (fontSize * mergeFactor).clamp(mergeMin, mergeMax);
  }

  /// Check if centerline mode should be used for this font size.
  bool shouldUseCenterline(double fontSize, {bool preferOutline = false}) {
    return !preferOutline && fontSize < threshold;
  }
}

/// Configuration for text vectorization parameters.
class TextVectorConfig {
  final double worldScale;
  final int blurK;
  final double cannyLo;
  final double cannyHi;
  final double minPerimeter;
  final double angleThresholdDeg;
  final int angleWindow;
  final double minStrokeLen;
  final int minStrokePoints;

  const TextVectorConfig({
    this.worldScale = 1.0,
    this.blurK = 3,
    this.cannyLo = 30,
    this.cannyHi = 120,
    this.minPerimeter = 6.0,
    this.angleThresholdDeg = 85,
    this.angleWindow = 3,
    this.minStrokeLen = 4.0,
    this.minStrokePoints = 3,
  });
}

/// Service for rendering text to vectorized strokes.
///
/// Handles the pipeline of text → PNG → vectorization with
/// support for both outline and centerline rendering modes.
class TextSketchService {
  final CenterlineConfig centerlineConfig;
  final TextVectorConfig vectorConfig;

  const TextSketchService({
    this.centerlineConfig = const CenterlineConfig(),
    this.vectorConfig = const TextVectorConfig(),
  });

  /// Render text to PNG image bytes.
  ///
  /// Returns the raw PNG bytes suitable for vectorization.
  Future<Uint8List> renderTextToPng(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );
    tp.paint(canvas, Offset(pad, pad));

    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// Render a single line of text to PNG with dimension info.
  ///
  /// Returns a [RenderedLine] containing the PNG bytes and pixel dimensions.
  Future<RenderedLine> renderTextLine(String text, double fontSize) async {
    final style = const TextStyle(color: Colors.black);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style.copyWith(fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();

    final pad = 10.0;
    final w = (tp.width + pad * 2).ceil();
    final h = (tp.height + pad * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );
    tp.paint(canvas, Offset(pad, pad));

    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);

    return RenderedLine(
      bytes: data!.buffer.asUint8List(),
      w: w.toDouble(),
      h: h.toDouble(),
    );
  }

  /// Get vectorization parameters for text.
  ///
  /// Returns a map of parameters suitable for the Vectorizer,
  /// adjusted based on whether centerline mode is active.
  Map<String, dynamic> getVectorizationParams({
    required double fontSize,
    required bool preferOutline,
  }) {
    final useCenterline = centerlineConfig.shouldUseCenterline(
      fontSize,
      preferOutline: preferOutline,
    );
    final mergeDist = useCenterline
        ? centerlineConfig.mergeDistanceFor(fontSize)
        : 10.0;

    return {
      'worldScale': vectorConfig.worldScale,
      'edgeMode': 'Canny',
      'blurK': vectorConfig.blurK,
      'cannyLo': vectorConfig.cannyLo,
      'cannyHi': vectorConfig.cannyHi,
      'epsilon': useCenterline ? centerlineConfig.epsilon : 0.8,
      'resampleSpacing': useCenterline ? centerlineConfig.resample : 1.0,
      'minPerimeter': vectorConfig.minPerimeter,
      'retrExternalOnly': false,
      'angleThresholdDeg': vectorConfig.angleThresholdDeg,
      'angleWindow': vectorConfig.angleWindow,
      'smoothPasses': useCenterline ? centerlineConfig.smoothPasses : 1,
      'mergeParallel': true,
      'mergeMaxDist': mergeDist,
      'minStrokeLen': vectorConfig.minStrokeLen,
      'minStrokePoints': vectorConfig.minStrokePoints,
    };
  }

  /// Calculate the scale factor needed for small fonts.
  ///
  /// Small fonts are scaled up for better vectorization quality,
  /// then scaled back down when placing strokes.
  double getScaleUpFactor(double fontSize) {
    return fontSize < 24 ? (24.0 / fontSize) : 1.0;
  }

  /// Calculate stitch gap for text strokes.
  ///
  /// Returns the maximum gap for stitching strokes together,
  /// scaled appropriately for the font size.
  double getStitchGap(double fontSize) {
    return (fontSize * 0.08).clamp(3.0, 18.0);
  }

  /// Calculate line height for multi-line text.
  double getLineHeight(double fontSize, {double lineHeightMultiplier = 1.25}) {
    return fontSize * lineHeightMultiplier;
  }

  /// Measure text dimensions without rendering.
  Size measureText(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: Colors.black),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Size(tp.width, tp.height);
  }

  /// Wrap text to fit within a maximum width.
  ///
  /// Uses a heuristic based on average character width.
  List<String> wrapText(String text, double fontSize, double maxWidth) {
    // Crude heuristic: average char width ≈ 0.55 * fontSize
    final avgCharWidth = fontSize * 0.55;
    final maxChars = (maxWidth / avgCharWidth).floor().clamp(8, 1000);

    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var currentLine = '';

    for (final word in words) {
      if (currentLine.isEmpty) {
        currentLine = word;
        continue;
      }
      if ((currentLine.length + 1 + word.length) <= maxChars) {
        currentLine += ' $word';
      } else {
        lines.add(currentLine);
        currentLine = word;
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine);
    }

    return lines;
  }
}
