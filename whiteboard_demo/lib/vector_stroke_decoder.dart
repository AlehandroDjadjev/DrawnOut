import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show debugPrint;

/// Decodes backend stroke payloads into polylines:
/// `List<List<Offset>>` where each inner list is one stroke.
///
/// Supports:
/// - vector_format: "polyline" with points as `List<List<num>>`
/// - vector_format: "bezier_cubic" with segments as `List<List<num>>`
/// - points/segments optionally packed as base64 Float32 arrays.
class VectorStrokeDecoder {
  static List<List<Offset>> decodeToPolylines(
    Map<String, dynamic> data, {
    double worldScale = 1.0,
    double? sourceWidth,
    double? sourceHeight,
    Endian floatEndian = Endian.little,
    bool isText = false,
    bool skipWorldSpace = false,
  }) {
    debugPrint('🔍 DECODE │ VectorStrokeDecoder.decodeToPolylines (vector_stroke_decoder.dart)');
    debugPrint('🔍 DECODE │   input: format=${(data['vector_format'] as String?) ?? "null"}, width=${data['width']}, height=${data['height']}');
    final strokesJson = data['strokes'];
    if (strokesJson is! List) {
      debugPrint('🔍 DECODE │   strokes is not List (${strokesJson.runtimeType}) → returning []');
      return const [];
    }
    debugPrint('🔍 DECODE │   strokes: ${strokesJson.length} items');

    final format =
        (data['vector_format'] as String?)?.toLowerCase() ?? 'polyline';

    final raw = <List<Offset>>[];

    if (format == 'bezier_cubic') {
      for (final s in strokesJson) {
        if (s is! Map) continue;

        final segs = _decodeSegmentsAny(s['segments'], endian: floatEndian);
        if (segs.isEmpty) continue;

        final pts = <Offset>[];
        for (final seg in segs) {
          if (seg.length < 8) continue;
          final p0 = Offset(seg[0], seg[1]);
          final c1 = Offset(seg[2], seg[3]);
          final c2 = Offset(seg[4], seg[5]);
          final p1 = Offset(seg[6], seg[7]);

          final steps = isText
              ? _recommendedStepsText(p0, c1, c2, p1)
              : _recommendedSteps(p0, c1, c2, p1);

          final sampled = _sampleCubicSegment(p0, c1, c2, p1, steps);
          if (pts.isEmpty) {
            pts.addAll(sampled);
          } else {
            pts.addAll(sampled.skip(1));
          }
        }

        final cleaned = isText ? pts : _removeTinySteps(pts);
        if (cleaned.length >= 2) raw.add(cleaned);
      }
    } else {
      for (final s in strokesJson) {
        if (s is! Map) continue;

        final ptsDecoded = _decodePointsAny(s['points'], endian: floatEndian);
        if (ptsDecoded.length >= 2) raw.add(ptsDecoded);
      }
    }

    debugPrint('🔍 DECODE │   raw polylines: ${raw.length} strokes, ${raw.fold<int>(0, (s, p) => s + p.length)} points');
    if (skipWorldSpace) return raw;

    final transformed = _toWorldSpace(
      raw,
      data: data,
      worldScale: worldScale,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    debugPrint('🔍 DECODE │   after _toWorldSpace: ${transformed.length} strokes');
    return transformed;
  }

  /// Decode segments from either `List<List<num>>` or base64 Float32 packed array.
  /// Returns list of 8-element lists [x0,y0,c1x,c1y,c2x,c2y,x1,y1].
  /// Use this when building RawCubicStroke or other color-aware pipelines.
  static List<List<double>> decodeSegments(
    dynamic segments, {
    Endian floatEndian = Endian.little,
  }) {
    return _decodeSegmentsAny(segments, endian: floatEndian);
  }

  /// Decode points from either `List<List<num>>` or base64 Float32 packed array.
  /// Returns list of Offset.
  static List<Offset> decodePoints(
    dynamic points, {
    Endian floatEndian = Endian.little,
  }) {
    return _decodePointsAny(points, endian: floatEndian);
  }

  // ---------- Packed/base64 decoding helpers ----------

  static List<List<double>> _decodeSegmentsAny(
    dynamic segments, {
    required Endian endian,
  }) {
    if (segments is List) {
      return segments
          .whereType<List>()
          .map((l) => l
              .whereType<num>()
              .map((n) => n.toDouble())
              .toList(growable: false))
          .where((l) => l.length >= 8)
          .toList(growable: false);
    }

    if (segments is String && segments.isNotEmpty) {
      final floats = _decodeBase64Float32(segments, endian: endian);
      final out = <List<double>>[];
      for (int i = 0; i + 7 < floats.length; i += 8) {
        out.add(floats.sublist(i, i + 8));
      }
      return out;
    }

    return const [];
  }

  static List<Offset> _decodePointsAny(
    dynamic points, {
    required Endian endian,
  }) {
    if (points is List) {
      final pts = <Offset>[];
      for (final p in points) {
        if (p is List && p.length >= 2) {
          final x = (p[0] as num).toDouble();
          final y = (p[1] as num).toDouble();
          pts.add(Offset(x, y));
        }
      }
      return pts;
    }

    if (points is String && points.isNotEmpty) {
      final floats = _decodeBase64Float32(points, endian: endian);
      final pts = <Offset>[];
      for (int i = 0; i + 1 < floats.length; i += 2) {
        pts.add(Offset(floats[i], floats[i + 1]));
      }
      return pts;
    }

    return const [];
  }

  static List<double> _decodeBase64Float32(
    String b64, {
    required Endian endian,
  }) {
    try {
      final bytes = base64Decode(b64);
      final bd = ByteData.sublistView(bytes);
      final count = bytes.length ~/ 4;
      final out = List<double>.filled(count, 0.0, growable: false);
      for (int i = 0; i < count; i++) {
        out[i] = bd.getFloat32(i * 4, endian).toDouble();
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // ---------- Cubic sampling (from working backend_vectorizer) ----------

  static List<Offset> _sampleCubicSegment(
      Offset p0, Offset c1, Offset c2, Offset p1, int n) {
    final pts = <Offset>[];
    for (int i = 0; i <= n; i++) {
      final t = i / n;
      final t2 = t * t;
      final t3 = t2 * t;
      final mt = 1 - t;
      final mt2 = mt * mt;
      final mt3 = mt2 * mt;
      final x =
          mt3 * p0.dx + 3 * mt2 * t * c1.dx + 3 * mt * t2 * c2.dx + t3 * p1.dx;
      final y =
          mt3 * p0.dy + 3 * mt2 * t * c1.dy + 3 * mt * t2 * c2.dy + t3 * p1.dy;
      pts.add(Offset(x, y));
    }
    return pts;
  }

  static int _recommendedSteps(Offset p0, Offset c1, Offset c2, Offset p1) {
    final controlLen =
        (c1 - p0).distance + (c2 - c1).distance + (p1 - c2).distance;
    final chord = (p1 - p0).distance;
    final bend = (controlLen - chord).abs();
    final byLen = (controlLen / 2.0).ceil();
    final byBend = (bend * 0.9).ceil();
    return (byLen + byBend).clamp(12, 40);
  }

  static int _recommendedStepsText(Offset p0, Offset c1, Offset c2, Offset p1) {
    final controlLen =
        (c1 - p0).distance + (c2 - c1).distance + (p1 - c2).distance;
    final chord = (p1 - p0).distance;
    final bend = (controlLen - chord).abs();
    final byLen = (controlLen / 3.0).ceil();
    final byBend = (bend * 1.2).ceil();
    return (byLen + byBend).clamp(18, 50);
  }

  static List<Offset> _removeTinySteps(List<Offset> pts) {
    if (pts.length < 3) return pts;

    final out = <Offset>[pts.first];
    for (int i = 1; i < pts.length; i++) {
      final p = pts[i];
      final isLast = i == pts.length - 1;
      if (isLast || (p - out.last).distance >= 0.18) {
        out.add(p);
      }
    }
    if (out.length < 3) return out;

    final smoothed = List<Offset>.from(out);
    for (int i = 1; i < out.length - 1; i++) {
      final a = out[i - 1];
      final b = out[i];
      final c = out[i + 1];
      smoothed[i] = Offset(
        (a.dx + 2 * b.dx + c.dx) / 4.0,
        (a.dy + 2 * b.dy + c.dy) / 4.0,
      );
    }
    return smoothed;
  }

  // ---------- Coordinate system normalization ----------

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
      if (sourceWidth != null && sourceWidth > 0) sx = sourceWidth / width;
      if (sourceHeight != null && sourceHeight > 0) sy = sourceHeight / height;
    } else {
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
        .map((stroke) => stroke
            .map((p) => Offset(
                  (p.dx - cx) * sx * worldScale,
                  (p.dy - cy) * sy * worldScale,
                ))
            .toList())
        .toList();
  }
}
