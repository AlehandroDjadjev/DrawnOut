import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../vector_stroke_decoder.dart';

/// Vectorizes images via backend API instead of local OpenCV.
/// Returns strokes as `List<List<Offset>>` (polylines) compatible with
/// StrokePlan and the rest of the whiteboard pipeline.
///
/// Decoding is delegated to VectorStrokeDecoder for consistency
/// and support of both JSON and base64-packed formats.
class BackendVectorizer {
  /// Fetch text strokes from create_text_object API (same as visual_whiteboard).
  /// Returns polylines in world space, or empty list on failure.
  static Future<List<List<Offset>>> fetchTextStrokesAsPolylines({
    required String baseUrl,
    required String prompt,
    required double x,
    required double y,
    required double letterSize,
    required double letterGap,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return [];

    try {
      final uri = Uri.parse('$base/api/whiteboard/objects/text/');
      final body = json.encode({
        'prompt': prompt,
        'x': x,
        'y': y,
        'letter_size': letterSize,
        'letter_gap': letterGap,
      });

      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 400) return [];

      final data = json.decode(resp.body);
      if (data is! Map || data['strokes'] is! List) return [];

      debugPrint('🔍 DECODE │ BackendVectorizer.fetchTextStrokesAsPolylines');
      debugPrint('🔍 DECODE │   backend response keys: ${data.keys.toList()}');
      debugPrint('🔍 DECODE │   vector_format=${data['vector_format']}, strokes=${(data['strokes'] as List).length} items');
      final decoded = VectorStrokeDecoder.decodeToPolylines(
        Map<String, dynamic>.from(data),
        worldScale: 1.0,
        isText: true,
        skipWorldSpace: true,
      );
      debugPrint('🔍 DECODE │   decoder: vector_stroke_decoder.dart → ${decoded.length} polylines');
      return decoded;
    } catch (e) {
      debugPrint('🔍 DECODE │   fetchTextStrokesAsPolylines error: $e');
      return [];
    }
  }

  /// POST image bytes to /api/wb/vectorize/vectorize/, parse result,
  /// and convert to `List<List<Offset>>`.
  static Future<List<List<Offset>>> vectorize({
    required String baseUrl,
    required Uint8List bytes,
    double worldScale = 1.0,
    double? sourceWidth,
    double? sourceHeight,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/api/wb/vectorize/vectorize/');
    final req = http.MultipartRequest('POST', uri);
    req.files.add(http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: 'image.png',
    ));
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      final body = resp.body;
      try {
        final j = json.decode(body) as Map?;
        throw StateError(j?['error']?.toString() ?? body);
      } catch (e) {
        if (e is StateError) rethrow;
        throw StateError(
            'HTTP ${resp.statusCode}: ${body.length > 200 ? body.substring(0, 200) : body}');
      }
    }

    final j = json.decode(resp.body) as Map?;
    if (j == null || j['ok'] != true) {
      throw StateError((j?['error'] ?? 'Unknown error').toString());
    }
    final result = j['result'];
    if (result is! Map) {
      throw StateError('Backend did not return stroke result');
    }

    debugPrint('🔍 DECODE │ BackendVectorizer.vectorize');
    debugPrint('🔍 DECODE │   backend result keys: ${result.keys.toList()}');
    final strokesList = result['strokes'];
    debugPrint('🔍 DECODE │   vector_format=${result['vector_format']}, strokes=${strokesList is List ? strokesList.length : "?"} items');
    final decoded = VectorStrokeDecoder.decodeToPolylines(
      Map<String, dynamic>.from(result),
      worldScale: worldScale,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      isText: false,
    );
    debugPrint('🔍 DECODE │   decoder: vector_stroke_decoder.dart → ${decoded.length} polylines');
    return decoded;
  }
}
