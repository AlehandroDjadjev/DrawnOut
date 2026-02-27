import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:http/http.dart' as http;

/// Vectorizes images via backend API instead of local OpenCV.
/// Returns strokes as List<List<Offset>> (polylines) compatible with
/// StrokePlan and the rest of the whiteboard pipeline.
class BackendVectorizer {
  /// POST image bytes to /api/wb/vectorize/vectorize/, parse result,
  /// and convert to List<List<Offset>>.
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
        throw StateError('HTTP ${resp.statusCode}: ${body.length > 200 ? body.substring(0, 200) : body}');
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

    return _decodeToPolylines(
      Map<String, dynamic>.from(result),
      worldScale: worldScale,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  /// Convert backend stroke JSON to List<List<Offset>>.
  static List<List<Offset>> _decodeToPolylines(
    Map<String, dynamic> data, {
    double worldScale = 1.0,
    double? sourceWidth,
    double? sourceHeight,
  }) {
    final strokesJson = data['strokes'];
    if (strokesJson is! List) return [];

    final format = (data['vector_format'] as String?)?.toLowerCase() ?? 'polyline';
    final raw = <List<Offset>>[];

    if (format == 'bezier_cubic') {
      for (final s in strokesJson) {
        if (s is! Map || s['segments'] is! List) continue;
        final List segsJson = s['segments'] as List;
        final pts = <Offset>[];
        for (final seg in segsJson) {
          if (seg is List && seg.length >= 8) {
            final sampled = _sampleCubicSegment(
              Offset((seg[0] as num).toDouble(), (seg[1] as num).toDouble()),
              Offset((seg[2] as num).toDouble(), (seg[3] as num).toDouble()),
              Offset((seg[4] as num).toDouble(), (seg[5] as num).toDouble()),
              Offset((seg[6] as num).toDouble(), (seg[7] as num).toDouble()),
              8,
            );
            if (pts.isEmpty) {
              pts.addAll(sampled);
            } else {
              pts.addAll(sampled.skip(1));
            }
          }
        }
        if (pts.length >= 2) raw.add(pts);
      }
    } else {
      for (final s in strokesJson) {
        if (s is! Map || s['points'] is! List) continue;
        final List ptsJson = s['points'] as List;
        final pts = <Offset>[];
        for (final p in ptsJson) {
          if (p is List && p.length >= 2) {
            pts.add(Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()));
          }
        }
        if (pts.length >= 2) raw.add(pts);
      }
    }
    return _toWorldSpace(
      raw,
      data: data,
      worldScale: worldScale,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
  }

  /// Sample cubic Bézier at n points (including start, excluding duplicate end of prev).
  static List<Offset> _sampleCubicSegment(Offset p0, Offset c1, Offset c2, Offset p1, int n) {
    final pts = <Offset>[];
    for (int i = 0; i <= n; i++) {
      final t = i / n;
      final t2 = t * t;
      final t3 = t2 * t;
      final mt = 1 - t;
      final mt2 = mt * mt;
      final mt3 = mt2 * mt;
      final x = mt3 * p0.dx + 3 * mt2 * t * c1.dx + 3 * mt * t2 * c2.dx + t3 * p1.dx;
      final y = mt3 * p0.dy + 3 * mt2 * t * c1.dy + 3 * mt * t2 * c2.dy + t3 * p1.dy;
      pts.add(Offset(x, y));
    }
    return pts;
  }

  /// Match local vectorizer semantics:
  /// convert image-space coordinates to world-space centered at (0, 0).
  static List<List<Offset>> _toWorldSpace(
    List<List<Offset>> raw, {
    required Map<String, dynamic> data,
    double worldScale = 1.0,
    double? sourceWidth,
    double? sourceHeight,
  }) {
    if (raw.isEmpty) return raw;

    double? width = (data['width'] as num?)?.toDouble();
    double? height = (data['height'] as num?)?.toDouble();
    double cx;
    double cy;
    double sx = 1.0;
    double sy = 1.0;

    if (width != null && height != null && width > 0 && height > 0) {
      cx = width / 2.0;
      cy = height / 2.0;
      if (sourceWidth != null && sourceWidth > 0) {
        sx = sourceWidth / width;
      }
      if (sourceHeight != null && sourceHeight > 0) {
        sy = sourceHeight / height;
      }
    } else {
      // Fallback if metadata is missing: derive center from stroke bounds.
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final stroke in raw) {
        for (final p in stroke) {
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
      }
      cx = (minX + maxX) / 2.0;
      cy = (minY + maxY) / 2.0;
    }

    return raw
        .map(
          (stroke) => stroke
              .map((p) => Offset(
                    (p.dx - cx) * sx * worldScale,
                    (p.dy - cy) * sy * worldScale,
                  ))
              .toList(),
        )
        .toList();
  }
}
