import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;

/// Backend object types
enum WhiteboardObjectKind { image, text }

/// Whiteboard object from backend
class WhiteboardObject {
  final String name;
  final WhiteboardObjectKind kind;
  final double posX;
  final double posY;
  final double scale;
  final double? letterSize;
  final double? letterGap;

  WhiteboardObject({
    required this.name,
    required this.kind,
    required this.posX,
    required this.posY,
    this.scale = 1.0,
    this.letterSize,
    this.letterGap,
  });

  factory WhiteboardObject.fromJson(Map<String, dynamic> json) {
    return WhiteboardObject(
      name: (json['name'] ?? '').toString(),
      kind: (json['kind'] ?? '').toString() == 'text'
          ? WhiteboardObjectKind.text
          : WhiteboardObjectKind.image,
      posX: (json['pos_x'] as num?)?.toDouble() ?? 0.0,
      posY: (json['pos_y'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      letterSize: (json['letter_size'] as num?)?.toDouble(),
      letterGap: (json['letter_gap'] as num?)?.toDouble(),
    );
  }

  Offset get position => Offset(posX, posY);
}

/// Service for syncing whiteboard state with backend
/// NOTE: Backend whiteboard API is currently disabled
class WhiteboardBackendService {
  final String baseUrl;
  bool enabled;

  WhiteboardBackendService({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.enabled = false,  // Disabled - backend API not ready
  });

  Uri _apiUri(String path) => Uri.parse('$baseUrl$path');

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
}
