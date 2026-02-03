import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Configuration for image vectorization.
class ImageVectorConfig {
  final double worldScale;
  final String edgeMode;
  final int blurK;
  final double cannyLo;
  final double cannyHi;
  final double epsilon;
  final double resampleSpacing;
  final double minPerimeter;
  final bool retrExternalOnly;
  final double angleThresholdDeg;
  final int angleWindow;
  final int smoothPasses;
  final bool mergeParallel;
  final double mergeMaxDist;
  final double minStrokeLen;
  final int minStrokePoints;

  const ImageVectorConfig({
    this.worldScale = 1.0,
    this.edgeMode = 'Canny',
    this.blurK = 3,
    this.cannyLo = 35,
    this.cannyHi = 140,
    this.epsilon = 0.9,
    this.resampleSpacing = 1.1,
    this.minPerimeter = 20.0,
    this.retrExternalOnly = false,
    this.angleThresholdDeg = 85,
    this.angleWindow = 3,
    this.smoothPasses = 2,
    this.mergeParallel = true,
    this.mergeMaxDist = 14.0,
    this.minStrokeLen = 16.0,
    this.minStrokePoints = 10,
  });

  /// Convert to map for Vectorizer.
  Map<String, dynamic> toMap() => {
        'worldScale': worldScale,
        'edgeMode': edgeMode,
        'blurK': blurK,
        'cannyLo': cannyLo,
        'cannyHi': cannyHi,
        'epsilon': epsilon,
        'resampleSpacing': resampleSpacing,
        'minPerimeter': minPerimeter,
        'retrExternalOnly': retrExternalOnly,
        'angleThresholdDeg': angleThresholdDeg,
        'angleWindow': angleWindow,
        'smoothPasses': smoothPasses,
        'mergeParallel': mergeParallel,
        'mergeMaxDist': mergeMaxDist,
        'minStrokeLen': minStrokeLen,
        'minStrokePoints': minStrokePoints,
      };
}

/// Result of fetching an image.
class ImageFetchResult {
  final Uint8List? bytes;
  final String? error;
  final String source; // 'url', 'base64', 'failed'

  const ImageFetchResult({
    this.bytes,
    this.error,
    required this.source,
  });

  bool get success => bytes != null && bytes!.isNotEmpty;
}

/// Placement information for an image on the whiteboard.
class ImagePlacement {
  final double x;
  final double y;
  final double width;
  final double height;
  final double? scale;

  const ImagePlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.scale,
  });

  /// Parse placement from a map (e.g., from JSON).
  factory ImagePlacement.fromMap(Map<String, dynamic> map) {
    return ImagePlacement(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      width: (map['width'] as num?)?.toDouble() ?? 200.0,
      height: (map['height'] as num?)?.toDouble() ?? 200.0,
      scale: (map['scale'] as num?)?.toDouble(),
    );
  }

  /// Apply scale factor if present.
  ImagePlacement withAppliedScale() {
    if (scale == null || scale! <= 0) return this;
    return ImagePlacement(
      x: x,
      y: y,
      width: width * scale!,
      height: height * scale!,
      scale: null,
    );
  }
}

/// Service for fetching and processing images for sketch rendering.
///
/// Handles image fetching from URLs (with CORS proxy support),
/// base64 decoding, and vectorization configuration.
class ImageSketchService {
  final String? baseUrl;
  final ImageVectorConfig vectorConfig;
  final Duration fetchTimeout;

  const ImageSketchService({
    this.baseUrl,
    this.vectorConfig = const ImageVectorConfig(),
    this.fetchTimeout = const Duration(seconds: 30),
  });

  /// Build a CORS-proxied URL for image fetching.
  ///
  /// This is needed for web platform to bypass CORS restrictions.
  String buildProxiedImageUrl(String imageUrl) {
    if (baseUrl == null || baseUrl!.isEmpty) {
      return imageUrl;
    }
    final base = baseUrl!.replaceAll(RegExp(r'/+$'), '');
    final encoded = Uri.encodeComponent(imageUrl);
    return '$base/api/wb_generate/proxy-image/?url=$encoded';
  }

  /// Fetch image bytes from a URL.
  ///
  /// Returns [ImageFetchResult] with the image bytes or error information.
  Future<ImageFetchResult> fetchImage(String imageUrl) async {
    try {
      final proxiedUrl = buildProxiedImageUrl(imageUrl);
      debugPrint('🖼️ Fetching image: $imageUrl');
      debugPrint('   Proxied URL: $proxiedUrl');

      final response = await http.get(Uri.parse(proxiedUrl)).timeout(
            fetchTimeout,
            onTimeout: () => throw Exception('Image fetch timed out'),
          );

      if (response.statusCode == 200) {
        debugPrint('   ✅ Fetched ${response.bodyBytes.length} bytes');
        return ImageFetchResult(
          bytes: response.bodyBytes,
          source: 'url',
        );
      } else {
        final error = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        debugPrint('   ❌ $error');
        return ImageFetchResult(
          error: error,
          source: 'failed',
        );
      }
    } catch (e) {
      debugPrint('   ❌ Image fetch failed: $e');
      return ImageFetchResult(
        error: e.toString(),
        source: 'failed',
      );
    }
  }

  /// Decode base64 image data.
  ///
  /// Returns [ImageFetchResult] with the decoded bytes or error information.
  ImageFetchResult decodeBase64(String base64Data) {
    try {
      debugPrint('🖼️ Decoding base64 image');
      final bytes = base64Decode(base64Data);
      debugPrint('   ✅ Decoded ${bytes.length} bytes');
      return ImageFetchResult(
        bytes: bytes,
        source: 'base64',
      );
    } catch (e) {
      debugPrint('   ❌ Base64 decode failed: $e');
      return ImageFetchResult(
        error: e.toString(),
        source: 'failed',
      );
    }
  }

  /// Fetch image from URL with base64 fallback.
  ///
  /// Tries URL first, then falls back to base64 if provided.
  Future<ImageFetchResult> fetchWithFallback({
    String? imageUrl,
    String? imageBase64,
    Map<String, dynamic>? metadata,
  }) async {
    // Resolve URL from multiple possible sources
    String? resolvedUrl = imageUrl;
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      resolvedUrl =
          metadata?['image_url'] as String? ?? metadata?['url'] as String?;
    }

    // Try URL first
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      final result = await fetchImage(resolvedUrl);
      if (result.success) return result;
    }

    // Fallback to base64
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      return decodeBase64(imageBase64);
    }

    return const ImageFetchResult(
      error: 'No image data available',
      source: 'failed',
    );
  }

  /// Get vectorization parameters for images/diagrams.
  Map<String, dynamic> getVectorizationParams() {
    return vectorConfig.toMap();
  }

  /// Calculate auto-placement for an image within a column.
  ///
  /// Returns placement centered horizontally in the available width.
  ImagePlacement calculateAutoPlacement({
    required double imageWidth,
    required double imageHeight,
    required double columnX,
    required double columnWidth,
    required double cursorY,
    required double pageHeight,
    required double pageBottom,
    required double gutterY,
    double maxWidthRatio = 0.4,
  }) {
    final maxW = columnWidth * maxWidthRatio;

    // Calculate scale to fit
    final scaleW = imageWidth == 0 ? 1.0 : maxW / imageWidth;
    final remainH = pageHeight - pageBottom - cursorY - gutterY;
    final scaleH = imageHeight == 0 ? scaleW : (remainH / imageHeight).clamp(0.1, scaleW);
    final effScale = scaleW < scaleH ? scaleW : scaleH;

    final targetW = imageWidth * effScale;
    final targetH = imageHeight * effScale;

    // Center horizontally
    final x = columnX + (columnWidth - targetW) / 2.0;

    return ImagePlacement(
      x: x,
      y: cursorY,
      width: targetW,
      height: targetH,
    );
  }

  /// Fetch a diagram from the backend API.
  ///
  /// Returns the image bytes or null if failed.
  Future<Uint8List?> fetchDiagram(String prompt, {String? size, String? quality}) async {
    if (baseUrl == null || baseUrl!.isEmpty) {
      debugPrint('❌ No base URL configured for diagram API');
      return null;
    }

    try {
      final base = baseUrl!.replaceAll(RegExp(r'/+$'), '');
      final url = Uri.parse('$base/api/lessons/diagram/');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'prompt': prompt,
              if (size != null) 'size': size,
              if (quality != null) 'quality': quality,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode ~/ 100 != 2) {
        debugPrint('❌ Diagram API error: ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final b64 = (body['image_b64'] ?? '') as String;

      if (b64.isEmpty) {
        debugPrint('❌ Empty image data from diagram API');
        return null;
      }

      return base64Decode(b64);
    } catch (e) {
      debugPrint('❌ Diagram fetch error: $e');
      return null;
    }
  }
}
