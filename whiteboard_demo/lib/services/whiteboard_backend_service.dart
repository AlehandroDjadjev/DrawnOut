import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;

/// Backend object types
enum WhiteboardObjectKind { image, text, sketchImage }

/// Whiteboard object from backend
class WhiteboardObject {
  final String name;
  final WhiteboardObjectKind kind;
  final double posX;
  final double posY;
  final double scale;
  final double? letterSize;
  final double? letterGap;
  final double? width;
  final double? height;
  final String? imageUrl;
  final Map<String, dynamic>? metadata;

  WhiteboardObject({
    required this.name,
    required this.kind,
    required this.posX,
    required this.posY,
    this.scale = 1.0,
    this.letterSize,
    this.letterGap,
    this.width,
    this.height,
    this.imageUrl,
    this.metadata,
  });

  factory WhiteboardObject.fromJson(Map<String, dynamic> json) {
    final kindStr = (json['kind'] ?? '').toString();
    WhiteboardObjectKind kind;
    switch (kindStr) {
      case 'text':
        kind = WhiteboardObjectKind.text;
        break;
      case 'sketch_image':
        kind = WhiteboardObjectKind.sketchImage;
        break;
      default:
        kind = WhiteboardObjectKind.image;
    }

    return WhiteboardObject(
      name: (json['name'] ?? '').toString(),
      kind: kind,
      posX: (json['pos_x'] as num?)?.toDouble() ?? 0.0,
      posY: (json['pos_y'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      letterSize: (json['letter_size'] as num?)?.toDouble(),
      letterGap: (json['letter_gap'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Offset get position => Offset(posX, posY);
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind == WhiteboardObjectKind.text 
        ? 'text' 
        : kind == WhiteboardObjectKind.sketchImage 
            ? 'sketch_image' 
            : 'image',
    'pos_x': posX,
    'pos_y': posY,
    'scale': scale,
    if (letterSize != null) 'letter_size': letterSize,
    if (letterGap != null) 'letter_gap': letterGap,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (imageUrl != null) 'image_url': imageUrl,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Service for syncing whiteboard state with backend
///
/// Provides CRUD operations for whiteboard objects (images, text, sketch_image)
/// and image proxy support for CORS-safe image fetching on web.
class WhiteboardBackendService {
  final String baseUrl;
  bool enabled;

  WhiteboardBackendService({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.enabled = false,  // Disabled by default - enable when backend API is ready
  });

  Uri _apiUri(String path) => Uri.parse('$baseUrl$path');

  // ─────────────────────────────────────────────────────────────────────────
  // Image Proxy (CORS workaround for web)
  // ─────────────────────────────────────────────────────────────────────────

  /// Build a CORS-safe proxied URL for web platforms
  ///
  /// On web, external images often fail due to CORS. This routes through
  /// the backend's image-proxy endpoint. On native platforms, returns
  /// the original URL unchanged.
  String buildProxiedImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return '';
    if (!kIsWeb) return rawUrl;

    final encodedUrl = Uri.encodeComponent(rawUrl);
    return '$baseUrl/api/lesson-pipeline/image-proxy/?url=$encodedUrl';
  }

  /// Fetch image bytes through the proxy (for web CORS safety)
  Future<Uint8List?> fetchImageBytes(
    String url, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final fetchUrl = buildProxiedImageUrl(url);
      debugPrint('Fetching image: $url');

      final response = await http.get(Uri.parse(fetchUrl)).timeout(
        timeout,
        onTimeout: () => throw Exception('Image fetch timed out'),
      );

      if (response.statusCode == 200) {
        debugPrint('   Fetched ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      }
      debugPrint('   HTTP ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('   Image fetch failed: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image CRUD Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Create an image object on the backend
  Future<void> createImage({
    required String fileName,
    required Offset origin,
    required double scale,
  }) async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/image/');
    final body = json.encode({
      'file_name': fileName,
      'x': origin.dx,
      'y': origin.dy,
      'scale': scale,
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Create a sketch_image object on the backend
  ///
  /// Sketch images are vectorized versions of raster images, rendered
  /// as hand-drawn strokes on the whiteboard.
  Future<void> createSketchImage({
    required String name,
    required String imageUrl,
    required Offset origin,
    required double width,
    required double height,
    double scale = 1.0,
    Map<String, dynamic>? metadata,
  }) async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/sketch_image/');
    final body = json.encode({
      'name': name,
      'image_url': imageUrl,
      'x': origin.dx,
      'y': origin.dy,
      'width': width,
      'height': height,
      'scale': scale,
      if (metadata != null) 'metadata': metadata,
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Text CRUD Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a text object on the backend
  Future<void> createText({
    required String prompt,
    required Offset origin,
    required double letterSize,
    required double letterGap,
  }) async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/text/');
    final body = json.encode({
      'prompt': prompt,
      'x': origin.dx,
      'y': origin.dy,
      'letter_size': letterSize,
      'letter_gap': letterGap,
    });

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Update a text object's content or position
  Future<void> updateText({
    required String name,
    String? prompt,
    Offset? origin,
    double? letterSize,
    double? letterGap,
  }) async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/text/$name/');
    final body = json.encode({
      if (prompt != null) 'prompt': prompt,
      if (origin != null) 'x': origin.dx,
      if (origin != null) 'y': origin.dy,
      if (letterSize != null) 'letter_size': letterSize,
      if (letterGap != null) 'letter_gap': letterGap,
    });

    final resp = await http.patch(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (resp.statusCode >= 400) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Common CRUD Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Delete an object from the backend
  Future<void> deleteObject(String name) async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/delete/');
    final body = json.encode({'name': name});

    final resp = await http.delete(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    // 404 is ok - already deleted
    if (resp.statusCode >= 400 && resp.statusCode != 404) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Load all objects from the backend
  Future<List<WhiteboardObject>> loadObjects() async {
    if (!enabled) return [];

    final uri = _apiUri('/api/whiteboard/objects/');
    final resp = await http.get(uri);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! Map || decoded['objects'] is! List) {
      throw Exception('Invalid response format');
    }

    final List objs = decoded['objects'] as List;
    return objs
        .whereType<Map<String, dynamic>>()
        .map((o) => WhiteboardObject.fromJson(o))
        .toList();
  }

  /// Clear all objects from the whiteboard
  Future<void> clearAll() async {
    if (!enabled) return;

    final uri = _apiUri('/api/whiteboard/objects/clear/');
    final resp = await http.post(uri);

    if (resp.statusCode >= 400) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  /// Get a specific object by name
  Future<WhiteboardObject?> getObject(String name) async {
    if (!enabled) return null;

    final uri = _apiUri('/api/whiteboard/objects/$name/');
    final resp = await http.get(uri);

    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response format');
    }

    return WhiteboardObject.fromJson(decoded);
  }
}
