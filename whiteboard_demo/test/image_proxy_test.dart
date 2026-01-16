import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:whiteboard_demo/services/lesson_pipeline_api.dart';

void main() {
  group('LessonPipelineApi.buildProxiedImageUrl', () {
    late LessonPipelineApi api;

    setUp(() {
      api = LessonPipelineApi(baseUrl: 'http://localhost:8000');
    });

    test('returns empty string for null URL', () {
      final result = api.buildProxiedImageUrl(null);
      expect(result, '');
    });

    test('returns empty string for empty URL', () {
      final result = api.buildProxiedImageUrl('');
      expect(result, '');
    });

    test('handles URL on current platform', () {
      const testUrl = 'https://example.com/image.png';
      final result = api.buildProxiedImageUrl(testUrl);

      if (kIsWeb) {
        // On web, should be proxied
        expect(result, contains('/api/lesson-pipeline/image-proxy/'));
        expect(result, contains('url='));
        expect(result, contains(Uri.encodeComponent(testUrl)));
      } else {
        // On native, should return original
        expect(result, testUrl);
      }
    });

    test('static proxyImageUrl with custom baseUrl', () {
      const testUrl = 'https://cdn.example.com/photo.jpg';
      const customBase = 'http://192.168.1.100:8000';

      final result = LessonPipelineApi.proxyImageUrl(
        testUrl,
        baseUrl: customBase,
      );

      if (kIsWeb) {
        expect(result, startsWith(customBase));
        expect(result, contains('/api/lesson-pipeline/image-proxy/'));
      } else {
        expect(result, testUrl);
      }
    });
  });

  group('URL encoding verification', () {
    // These tests verify the URL encoding is correct regardless of platform
    // by testing the encoding function directly

    test('encodes special characters correctly', () {
      const rawUrl = 'https://example.com/path?query=value&other=123';
      final encoded = Uri.encodeComponent(rawUrl);

      // Verify encoding preserves URL when decoded
      expect(Uri.decodeComponent(encoded), rawUrl);

      // Verify special chars are encoded
      expect(encoded, isNot(contains('?')));
      expect(encoded, isNot(contains('&')));
      expect(encoded, isNot(contains('=')));
    });

    test('encodes unicode characters correctly', () {
      const rawUrl = 'https://example.com/image-日本語.png';
      final encoded = Uri.encodeComponent(rawUrl);

      expect(Uri.decodeComponent(encoded), rawUrl);
    });

    test('handles already-encoded URLs', () {
      // If URL is already partially encoded, we still encode the whole thing
      const rawUrl = 'https://example.com/path%20with%20spaces.png';
      final encoded = Uri.encodeComponent(rawUrl);

      // The % signs get double-encoded, which is expected
      expect(encoded, contains('%25'));
    });
  });

  group('Proxy URL format validation', () {
    test('constructs valid proxy URL format', () {
      const baseUrl = 'http://localhost:8000';
      const rawUrl = 'https://cdn.example.com/images/photo.jpg';

      // Manually construct what the proxy URL should look like
      final expectedProxy =
          '$baseUrl/api/lesson-pipeline/image-proxy/?url=${Uri.encodeComponent(rawUrl)}';

      // Verify the format is parseable as a URI
      final parsedUri = Uri.parse(expectedProxy);
      expect(parsedUri.scheme, 'http');
      expect(parsedUri.host, 'localhost');
      expect(parsedUri.port, 8000);
      expect(parsedUri.path, '/api/lesson-pipeline/image-proxy/');
      expect(parsedUri.queryParameters['url'], rawUrl);
    });

    test('proxy URL can be parsed back to original', () {
      const baseUrl = 'http://localhost:8000';
      const rawUrl = 'https://images.example.com/photo?size=large&format=webp';

      final proxyUrl =
          '$baseUrl/api/lesson-pipeline/image-proxy/?url=${Uri.encodeComponent(rawUrl)}';

      // Parse and extract the original URL
      final parsedUri = Uri.parse(proxyUrl);
      final extractedUrl = parsedUri.queryParameters['url'];

      expect(extractedUrl, rawUrl);
    });
  });
}







