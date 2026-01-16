import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

/// Service for interacting with the lesson pipeline API
class LessonPipelineApi {
  final String baseUrl;

  LessonPipelineApi({this.baseUrl = 'http://localhost:8000'});

  // ─────────────────────────────────────────────────────────────────────────
  // Image Proxy Helper (CORS workaround for web)
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds a CORS-safe image URL by proxying through the backend on web.
  ///
  /// On web platforms, external image URLs often fail due to CORS restrictions.
  /// This helper routes the request through the backend's image-proxy endpoint.
  ///
  /// On non-web platforms, returns the original URL unchanged.
  ///
  /// Example:
  /// ```dart
  /// final safeUrl = api.buildProxiedImageUrl('https://example.com/image.png');
  /// // On web: http://localhost:8000/api/lesson-pipeline/image-proxy/?url=https%3A%2F%2Fexample.com%2Fimage.png
  /// // On native: https://example.com/image.png
  /// ```
  String buildProxiedImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return '';
    }

    // On non-web platforms, return the URL directly (no CORS issues)
    if (!kIsWeb) {
      return rawUrl;
    }

    // On web, proxy through backend to avoid CORS
    final encodedUrl = Uri.encodeComponent(rawUrl);
    final proxiedUrl = '$baseUrl/api/lesson-pipeline/image-proxy/?url=$encodedUrl';
    
    debugPrint('🔗 Proxying image URL for web: $rawUrl → $proxiedUrl');
    
    return proxiedUrl;
  }

  /// Static version for use without an instance (uses default localhost)
  static String proxyImageUrl(String? rawUrl, {String baseUrl = 'http://localhost:8000'}) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return '';
    }

    if (!kIsWeb) {
      return rawUrl;
    }

    final encodedUrl = Uri.encodeComponent(rawUrl);
    return '$baseUrl/api/lesson-pipeline/image-proxy/?url=$encodedUrl';
  }

  /// Generate a complete lesson with intelligent image integration
  Future<LessonPipelineResult> generateLesson({
    required String prompt,
    String subject = 'General',
    double durationTarget = 60.0,
  }) async {
    final url = Uri.parse('$baseUrl/api/lesson-pipeline/generate/');

    print('🎯 Generating lesson for: $prompt');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'prompt': prompt,
          'subject': subject,
          'duration_target': durationTarget,
        }),
      ).timeout(
        const Duration(minutes: 5), // Lesson generation can take a while
        onTimeout: () {
          throw Exception('Lesson generation timed out after 5 minutes');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ok'] == true) {
          print('✅ Lesson generated successfully');
          return LessonPipelineResult.fromJson(data['lesson']);
        } else {
          throw Exception(data['error'] ?? 'Unknown error');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Lesson generation failed: $e');
      rethrow;
    }
  }

  /// Check health of all pipeline services
  Future<Map<String, dynamic>> checkHealth() async {
    final url = Uri.parse('$baseUrl/api/lesson-pipeline/health/');

    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200 || response.statusCode == 503) {
        return jsonDecode(response.body);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Health check failed: $e');
      rethrow;
    }
  }
}

/// Result from lesson pipeline generation
class LessonPipelineResult {
  final String id;
  final String promptId;
  final String content;
  final List<ResolvedImage> images;
  final String topicId;
  final int indexedImageCount;

  LessonPipelineResult({
    required this.id,
    required this.promptId,
    required this.content,
    required this.images,
    required this.topicId,
    required this.indexedImageCount,
  });

  factory LessonPipelineResult.fromJson(Map<String, dynamic> json) {
    return LessonPipelineResult(
      id: json['id'] ?? '',
      promptId: json['prompt_id'] ?? '',
      content: json['content'] ?? '',
      images: (json['images'] as List<dynamic>?)
              ?.map((i) => ResolvedImage.fromJson(i))
              .toList() ??
          [],
      topicId: json['topic_id'] ?? '',
      indexedImageCount: json['indexed_image_count'] ?? 0,
    );
  }
}

/// Resolved image with tag and URLs
class ResolvedImage {
  final ImageTag tag;
  final String baseImageUrl;
  final String finalImageUrl;
  final Map<String, dynamic> metadata;

  ResolvedImage({
    required this.tag,
    required this.baseImageUrl,
    required this.finalImageUrl,
    required this.metadata,
  });

  factory ResolvedImage.fromJson(Map<String, dynamic> json) {
    return ResolvedImage(
      tag: ImageTag.fromJson(json['tag'] ?? {}),
      baseImageUrl: json['base_image_url'] ?? '',
      finalImageUrl: json['final_image_url'] ?? '',
      metadata: json['metadata'] ?? {},
    );
  }
}

/// Image tag from script
class ImageTag {
  final String id;
  final String prompt;
  final String? style;
  final String? aspectRatio;
  final String? size;
  final double? guidanceScale;
  final double? strength;

  ImageTag({
    required this.id,
    required this.prompt,
    this.style,
    this.aspectRatio,
    this.size,
    this.guidanceScale,
    this.strength,
  });

  factory ImageTag.fromJson(Map<String, dynamic> json) {
    return ImageTag(
      id: json['id'] ?? '',
      prompt: json['prompt'] ?? '',
      style: json['style'],
      aspectRatio: json['aspect_ratio'],
      size: json['size'],
      guidanceScale: json['guidance_scale']?.toDouble(),
      strength: json['strength']?.toDouble(),
    );
  }
}



