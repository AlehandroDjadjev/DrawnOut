import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for interacting with the lesson pipeline API
class LessonPipelineApi {
  final String baseUrl;

  LessonPipelineApi({this.baseUrl = 'http://localhost:8000'});

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









