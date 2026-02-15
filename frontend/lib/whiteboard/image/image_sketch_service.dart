import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../core/stroke_plan.dart';
import '../layout/layout_state.dart';
import '../services/vectorizer.dart';

/// Configuration for image vectorization
class ImageVectorConfig {
  final String edgeMode;
  final int blurK;
  final int cannyLo;
  final int cannyHi;
  final double epsilon;
  final double resampleSpacing;
  final double minPerimeter;
  final bool retrExternalOnly;
  final int angleThresholdDeg;
  final int angleWindow;
  final int smoothPasses;
  final bool mergeParallel;
  final double mergeMaxDist;
  final double minStrokeLen;
  final int minStrokePoints;

  const ImageVectorConfig({
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

  static const ImageVectorConfig defaultConfig = ImageVectorConfig();
}

/// Result of sketching an image
class ImageSketchResult {
  /// Whether the operation succeeded
  final bool success;

  /// Generated strokes (empty if failed)
  final List<List<Offset>> strokes;

  /// The placement used
  final ImagePlacementResult? placement;

  /// Error message if failed
  final String? error;

  /// Original image dimensions
  final int? imageWidth;
  final int? imageHeight;

  const ImageSketchResult({
    required this.success,
    this.strokes = const [],
    this.placement,
    this.error,
    this.imageWidth,
    this.imageHeight,
  });

  factory ImageSketchResult.failure(String error) {
    return ImageSketchResult(success: false, error: error);
  }
}

/// Service for fetching, vectorizing, and placing images on the whiteboard
class ImageSketchService {
  final String baseUrl;
  final ImageVectorConfig vectorConfig;
  final double worldScale;
  late final AuthService _authService;

  ImageSketchService({
    this.baseUrl = 'http://localhost:8000',
    this.vectorConfig = const ImageVectorConfig(),
    this.worldScale = 1.0,
  }) {
    _authService = AuthService(baseUrl: baseUrl);
  }

  /// Build a CORS-safe proxied URL for web platforms
  String buildProxiedImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (!kIsWeb) return rawUrl;

    final encodedUrl = Uri.encodeComponent(rawUrl);
    return '$baseUrl/api/lesson-pipeline/image-proxy/?url=$encodedUrl';
  }

  /// Fetch image bytes from a URL with optional proxy for CORS
  Future<Uint8List?> fetchImageBytes(
    String url, {
    Duration timeout = const Duration(seconds: 30),
    bool useProxy = true,
  }) async {
    try {
      final fetchUrl = useProxy ? buildProxiedImageUrl(url) : url;
      debugPrint('🖼️ Fetching image: $url');
      if (useProxy && kIsWeb) {
        debugPrint('   Proxied URL: $fetchUrl');
      }

      final response = await _authService.authenticatedGet(fetchUrl);

      if (response.statusCode == 200) {
        debugPrint('   ✅ Fetched ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        debugPrint('   ❌ HTTP ${response.statusCode}: ${response.reasonPhrase}');
        return null;
      }
    } catch (e) {
      debugPrint('   ❌ Image fetch failed: $e');
      return null;
    }
  }

  /// Decode base64 image data
  Uint8List? decodeBase64Image(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return null;

    try {
      debugPrint('🖼️ Decoding base64 image');
      final bytes = base64Decode(base64Data);
      debugPrint('   ✅ Decoded ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      debugPrint('   ❌ Base64 decode failed: $e');
      return null;
    }
  }

  /// Decode image bytes to get dimensions
  Future<ui.Image?> decodeImage(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('❌ Image decode failed: $e');
      return null;
    }
  }

  /// Vectorize image bytes to strokes
  Future<List<List<Offset>>> vectorizeImage(
    Uint8List bytes, {
    ImageVectorConfig? config,
  }) async {
    final cfg = config ?? vectorConfig;

    try {
      return await Vectorizer.vectorize(
        bytes: bytes,
        worldScale: worldScale,
        edgeMode: cfg.edgeMode,
        blurK: cfg.blurK,
        cannyLo: cfg.cannyLo.toDouble(),
        cannyHi: cfg.cannyHi.toDouble(),
        epsilon: cfg.epsilon,
        resampleSpacing: cfg.resampleSpacing,
        minPerimeter: cfg.minPerimeter,
        retrExternalOnly: cfg.retrExternalOnly,
        angleThresholdDeg: cfg.angleThresholdDeg.toDouble(),
        angleWindow: cfg.angleWindow,
        smoothPasses: cfg.smoothPasses,
        mergeParallel: cfg.mergeParallel,
        mergeMaxDist: cfg.mergeMaxDist,
        minStrokeLen: cfg.minStrokeLen,
        minStrokePoints: cfg.minStrokePoints,
      );
    } catch (e) {
      debugPrint('❌ Vectorization failed: $e');
      return [];
    }
  }

  /// Filter strokes to remove small/decorative ones
  List<List<Offset>> filterStrokes(
    List<List<Offset>> strokes, {
    double minLength = 24.0,
    double minExtent = 8.0,
  }) {
    return StrokePlan(strokes)
        .filterStrokes(minLength: minLength, minExtent: minExtent)
        .strokes;
  }

  /// Transform strokes to fit a target placement
  ///
  /// [strokes] - Original strokes from vectorization
  /// [imageWidth] - Original image width
  /// [placement] - Target placement on the whiteboard
  /// [pageConfig] - Page configuration for coordinate conversion
  List<List<Offset>> transformStrokes(
    List<List<Offset>> strokes,
    int imageWidth,
    ImagePlacementResult placement,
    PageConfig pageConfig,
  ) {
    // Calculate scale factor (image px → target size)
    final effScale = placement.width / math.max(1, imageWidth);

    // Convert content-space to world-space
    final worldTopLeft = Offset(
      placement.x - (pageConfig.width / 2),
      placement.y - (pageConfig.height / 2),
    );
    final centerOffset = Offset(placement.width / 2.0, placement.height / 2.0);
    final centerWorld = worldTopLeft + centerOffset;

    return strokes
        .map((s) => s.map((p) => (p * effScale) + centerWorld).toList())
        .toList();
  }

  /// Complete sketch_image pipeline: fetch, vectorize, place, and transform
  ///
  /// This is the main entry point for processing sketch_image actions.
  Future<ImageSketchResult> sketchImageFromUrl({
    String? imageUrl,
    String? imageBase64,
    Map<String, dynamic>? placement,
    Map<String, dynamic>? metadata,
    required LayoutState layoutState,
    ImageVectorConfig? vectorConfig,
  }) async {
    final cfg = layoutState.config;

    // ── Step 1: Resolve the image URL ──────────────────────────────────────
    String? resolvedUrl = imageUrl;

    // Try metadata fallbacks if direct URL is empty
    if (resolvedUrl == null || resolvedUrl.isEmpty) {
      resolvedUrl = metadata?['image_url'] as String? ??
          metadata?['url'] as String?;
    }

    // ── Step 2: Get image bytes ────────────────────────────────────────────
    Uint8List? imageBytes;

    // Try fetching from URL first
    if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
      imageBytes = await fetchImageBytes(resolvedUrl);
    }

    // Fallback to base64 if URL fetch failed
    if (imageBytes == null && imageBase64 != null) {
      imageBytes = decodeBase64Image(imageBase64);
    }

    // If we still have no image, give up gracefully
    if (imageBytes == null || imageBytes.isEmpty) {
      debugPrint('⚠️ No image data available, skipping sketch_image');
      return ImageSketchResult.failure('No image data available');
    }

    // ── Step 3: Decode image to get dimensions ─────────────────────────────
    final img = await decodeImage(imageBytes);
    if (img == null) {
      return ImageSketchResult.failure('Failed to decode image');
    }

    // ── Step 4: Calculate placement ────────────────────────────────────────
    final p = placement ?? {};
    final hasExplicitPlacement = p.containsKey('x') && p.containsKey('y');

    final placementResult = LayoutService.calculateImagePlacement(
      layoutState,
      imageWidth: img.width.toDouble(),
      imageHeight: img.height.toDouble(),
      explicitX: hasExplicitPlacement ? (p['x'] as num?)?.toDouble() : null,
      explicitY: hasExplicitPlacement ? (p['y'] as num?)?.toDouble() : null,
      explicitWidth: (p['width'] as num?)?.toDouble(),
      explicitHeight: (p['height'] as num?)?.toDouble(),
      scale: (p['scale'] as num?)?.toDouble(),
    );

    debugPrint(
        '   📐 Placement: (${placementResult.x}, ${placementResult.y}) '
        'size: ${placementResult.width}x${placementResult.height}');

    // ── Step 5: Vectorize the image ────────────────────────────────────────
    final strokes = await vectorizeImage(imageBytes, config: vectorConfig);

    if (strokes.isEmpty) {
      debugPrint('⚠️ Vectorization produced no strokes');
      return ImageSketchResult.failure('Vectorization produced no strokes');
    }

    debugPrint('   ✏️ Vectorized: ${strokes.length} strokes');

    // ── Step 6: Filter and transform strokes ───────────────────────────────
    final filtered = filterStrokes(strokes);
    final transformed = transformStrokes(
      filtered,
      img.width,
      placementResult,
      cfg.page,
    );

    // ── Step 7: Update layout state ────────────────────────────────────────
    layoutState.blocks.add(DrawnBlock(
      id: 'sketch_img_${layoutState.blocks.length + 1}',
      type: 'sketch_image',
      bbox: placementResult.bbox,
      meta: {
        'w': img.width,
        'h': img.height,
        'url': resolvedUrl,
        if (metadata != null) ...metadata,
      },
    ));

    // Advance cursor for next content
    layoutState.cursorY =
        placementResult.y + placementResult.height + cfg.gutterY * 1.25;

    debugPrint('   ✅ Added ${transformed.length} strokes');

    return ImageSketchResult(
      success: true,
      strokes: transformed,
      placement: placementResult,
      imageWidth: img.width,
      imageHeight: img.height,
    );
  }
}
