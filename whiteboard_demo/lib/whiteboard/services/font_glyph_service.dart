import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/stroke_types.dart' as st;

// ── Data types ───────────────────────────────────────────────────────────────

/// Font-wide metrics loaded from `/api/wb/pipeline/font/metrics/`.
class FontMetrics {
  /// Total image height the glyphs were generated at (px in font space).
  final double imageHeight;

  /// Total image width of the glyph bitmaps (px in font space).
  final double imageWidth;

  /// Font size used during glyph generation (px in font space).
  final double fontSizePx;

  /// Ascent above baseline (px in font space).
  final double ascentPx;

  /// Descent below baseline (px in font space).
  final double descentPx;

  /// Full line height = ascent + descent (px in font space).
  final double lineHeightPx;

  const FontMetrics({
    required this.imageHeight,
    required this.imageWidth,
    required this.fontSizePx,
    required this.ascentPx,
    required this.descentPx,
    required this.lineHeightPx,
  });

  factory FontMetrics.fromJson(Map<String, dynamic> j) => FontMetrics(
        imageHeight: (j['image_height'] as num?)?.toDouble() ?? 2048.0,
        imageWidth: (j['image_width'] as num?)?.toDouble() ?? 2048.0,
        fontSizePx: (j['font_size_px'] as num?)?.toDouble() ?? 512.0,
        ascentPx: (j['ascent_px'] as num?)?.toDouble() ?? 475.0,
        descentPx: (j['descent_px'] as num?)?.toDouble() ?? 123.0,
        lineHeightPx: (j['line_height_px'] as num?)?.toDouble() ?? 598.0,
      );
}

/// One cubic Bézier segment inside a glyph.
class _GlyphSegment {
  final Offset p0, c1, c2, p1;
  const _GlyphSegment(
      {required this.p0,
      required this.c1,
      required this.c2,
      required this.p1});
}

/// One stroke inside a glyph (list of cubic segments).
class _GlyphStroke {
  final List<_GlyphSegment> segments;
  const _GlyphStroke(this.segments);
}

/// Parsed glyph data — cubic strokes in font image space + bounding rect.
class GlyphData {
  final List<_GlyphStroke> strokes;

  /// Bounding box in font image space (0..imageWidth × 0..imageHeight).
  final Rect bounds;

  const GlyphData({required this.strokes, required this.bounds});

  bool get isEmpty => strokes.isEmpty;
}

// ── FontGlyphService ──────────────────────────────────────────────────────────

/// Fetches handwriting font glyphs from the whiteboard_backend API and renders
/// text as cubic Bézier polylines — identical visual quality to DrawnOutWhiteboard.
///
/// Glyphs and metrics are cached for the lifetime of the app; no re-fetching.
///
/// Endpoints consumed:
///   GET <baseUrl>/font/metrics/              → `{ok, metrics}`
///   GET <baseUrl>/font/glyph/<hex4>/         → `{ok, glyph}`
///
/// (Base URL must already include the prefix, e.g. `/api/wb/pipeline/`.)
class FontGlyphService {
  static const int _stepsPerSegment = 18;
  static const double _spaceWidthFactor = 0.5;

  // In-memory caches (shared across all callers)
  static FontMetrics? _metrics;
  static bool _metricsFetchAttempted = false;
  static final Map<int, GlyphData?> _glyphCache = {};

  // ── Metrics ────────────────────────────────────────────────────────────────

  /// Returns cached [FontMetrics], fetching once from [baseUrl] on first call.
  static Future<FontMetrics?> loadMetrics(String baseUrl) async {
    if (_metricsFetchAttempted) return _metrics;
    _metricsFetchAttempted = true;

    try {
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse('${base}font/metrics/');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['metrics'] is Map) {
          _metrics = FontMetrics.fromJson(
              body['metrics'] as Map<String, dynamic>);
          debugPrint('✅ FontGlyphService: metrics loaded '
              '(lineHeight=${_metrics!.lineHeightPx})');
        }
      }
    } catch (e) {
      debugPrint('⚠️ FontGlyphService: metrics fetch failed: $e');
    }
    return _metrics;
  }

  /// Returns a [GlyphData] for [codeUnit], fetching once from [baseUrl].
  /// Returns null if not found or on error.
  static Future<GlyphData?> loadGlyph(String baseUrl, int codeUnit) async {
    if (_glyphCache.containsKey(codeUnit)) return _glyphCache[codeUnit];

    final hex = codeUnit.toRadixString(16).padLeft(4, '0');
    GlyphData? result;

    try {
      final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
      final uri = Uri.parse('${base}font/glyph/$hex/');
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['glyph'] is Map) {
          result = _parseGlyphJson(
              body['glyph'] as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('⚠️ FontGlyphService: glyph $hex fetch failed: $e');
    }

    _glyphCache[codeUnit] = result;
    return result;
  }

  // ── Text layout + rendering ────────────────────────────────────────────────

  /// Render [lines] of text to world-space polylines.
  ///
  /// Parameters mirror DrawnOutWhiteboard's `_writeTextPromptLocal`:
  ///   [topLeft]            – top-left of the text block in world coordinates.
  ///   [fontSize]           – desired letter height in world pixels.
  ///   [lineHeightMultiplier] – vertical spacing between lines.
  ///   [letterGapFactor]    – inter-letter gap as a fraction of [fontSize].
  ///   [baseUrl]            – prefix for the whiteboard_backend API.
  ///
  /// Returns an empty list if metrics or glyphs cannot be loaded.
  static Future<List<List<Offset>>> renderLines({
    required List<String> lines,
    required Offset topLeft,
    required double fontSize,
    required String baseUrl,
    double lineHeightMultiplier = 1.25,
    double letterGapFactor = 0.08,
  }) async {
    final metrics = await loadMetrics(baseUrl);
    if (metrics == null) return const [];

    final scale = fontSize / metrics.lineHeightPx;
    final letterGap = fontSize * letterGapFactor;
    final lineAdvance = fontSize * lineHeightMultiplier;

    // The glyph baseline in font image space is at imageHeight/2.
    // We want the top of the ascent to align with topLeft.dy, so:
    //   ascent top  = baseline - ascentPx * scale
    //   world baseline for line i = topLeft.dy + ascentPx*scale + i*lineAdvance
    final baselineY0 =
        topLeft.dy + metrics.ascentPx * scale;

    final out = <List<Offset>>[];

    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      if (line.trim().isEmpty) continue;

      final baselineY = baselineY0 + lineIdx * lineAdvance;
      // Baseline glyph origin (y=imageHeight/2 in font space → baselineY)
      final baselineGlyphScaled = (metrics.imageHeight / 2.0) * scale;

      double cursorX = topLeft.dx;

      for (int i = 0; i < line.length; i++) {
        final ch = line[i];
        if (ch == ' ') {
          cursorX += fontSize * _spaceWidthFactor;
          continue;
        }

        final code = ch.codeUnitAt(0);
        final glyph = await loadGlyph(baseUrl, code);
        if (glyph == null || glyph.isEmpty) {
          cursorX += fontSize * _spaceWidthFactor;
          continue;
        }

        final gb = glyph.bounds;
        final glyphWidth = math.max(gb.width, 1e-3);
        final glyphLeft = gb.left;

        // Place leftmost stroke edge at cursorX
        final letterOffsetX = cursorX - glyphLeft * scale;
        // Map glyph center-height to baseline
        final letterOffsetY = baselineY - baselineGlyphScaled;

        for (final stroke in glyph.strokes) {
          final pts = _sampleStroke(stroke, scale: scale);
          if (pts.length < 2) continue;
          final placed = pts
              .map((p) => Offset(
                    p.dx + letterOffsetX,
                    p.dy + letterOffsetY,
                  ))
              .toList(growable: false);
          out.add(placed);
        }

        cursorX += glyphWidth * scale + letterGap;
      }
    }

    return out;
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  static GlyphData? _parseGlyphJson(Map<String, dynamic> json) {
    final strokesRaw = json['strokes'];
    if (strokesRaw is! List) return null;

    final strokes = <_GlyphStroke>[];

    for (final s in strokesRaw) {
      if (s is! Map) continue;
      final segsRaw = s['segments'];
      if (segsRaw is! List) continue;

      final segs = <_GlyphSegment>[];
      for (final seg in segsRaw) {
        if (seg is List && seg.length >= 8) {
          segs.add(_GlyphSegment(
            p0: Offset(
                (seg[0] as num).toDouble(), (seg[1] as num).toDouble()),
            c1: Offset(
                (seg[2] as num).toDouble(), (seg[3] as num).toDouble()),
            c2: Offset(
                (seg[4] as num).toDouble(), (seg[5] as num).toDouble()),
            p1: Offset(
                (seg[6] as num).toDouble(), (seg[7] as num).toDouble()),
          ));
        }
      }
      if (segs.isNotEmpty) strokes.add(_GlyphStroke(segs));
    }

    if (strokes.isEmpty) return null;

    final bounds = _computeBounds(strokes);
    return GlyphData(strokes: strokes, bounds: bounds);
  }

  // ── Sampling ───────────────────────────────────────────────────────────────

  static List<Offset> _sampleStroke(_GlyphStroke s, {required double scale}) {
    final pts = <Offset>[];
    bool first = true;
    for (final seg in s.segments) {
      for (int i = 0; i <= _stepsPerSegment; i++) {
        final t = i / _stepsPerSegment;
        final p = _evalCubic(seg, t) * scale;
        if (!first && (p - pts.last).distance < 0.05) continue;
        pts.add(p);
        first = false;
      }
    }
    return pts;
  }

  static Offset _evalCubic(_GlyphSegment seg, double t) {
    final mt = 1.0 - t;
    final mt2 = mt * mt;
    final t2 = t * t;
    return Offset(
      mt2 * mt * seg.p0.dx +
          3 * mt2 * t * seg.c1.dx +
          3 * mt * t2 * seg.c2.dx +
          t2 * t * seg.p1.dx,
      mt2 * mt * seg.p0.dy +
          3 * mt2 * t * seg.c1.dy +
          3 * mt * t2 * seg.c2.dy +
          t2 * t * seg.p1.dy,
    );
  }

  // ── Geometry ───────────────────────────────────────────────────────────────

  static Rect _computeBounds(List<_GlyphStroke> strokes) {
    double minX = double.infinity,
        minY = double.infinity,
        maxX = -double.infinity,
        maxY = -double.infinity;
    for (final s in strokes) {
      for (final seg in s.segments) {
        for (final p in [seg.p0, seg.c1, seg.c2, seg.p1]) {
          if (p.dx < minX) minX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy > maxY) maxY = p.dy;
        }
      }
    }
    if (minX == double.infinity) return const Rect.fromLTWH(0, 0, 1, 1);
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  // ── Cache management ───────────────────────────────────────────────────────

  /// Warms up the glyph cache for a set of characters in the background.
  ///
  /// Call this early (e.g. on app start) with commonly used chars so the
  /// first lesson doesn't experience fetch latency.
  static Future<void> warmupCache(String baseUrl,
      {String chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?-+'}) async {
    await loadMetrics(baseUrl);
    final unique = chars.codeUnits.toSet();
    await Future.wait(
      unique.where((c) => c != 32).map((c) => loadGlyph(baseUrl, c)),
    );
    debugPrint(
        '✅ FontGlyphService: warmed up ${unique.length} glyphs');
  }

  /// Clear all cached data (useful for testing or server URL changes).
  static void clearCache() {
    _metrics = null;
    _metricsFetchAttempted = false;
    _glyphCache.clear();
  }

  /// Load a glyph and return as [st.GlyphData] (stroke_types) for use with
  /// StrokeBuilderService.buildStrokesForText. Matches DrawnOutWhiteboard format.
  static Future<st.GlyphData?> loadGlyphAsStrokeTypes(
      String baseUrl, int codeUnit) async {
    final internal = await loadGlyph(baseUrl, codeUnit);
    if (internal == null || internal.strokes.isEmpty) return null;
    final cubics = <st.StrokeCubic>[];
    for (final s in internal.strokes) {
      final segs = <st.CubicSegment>[];
      for (final seg in s.segments) {
        segs.add(st.CubicSegment(
          p0: seg.p0,
          c1: seg.c1,
          c2: seg.c2,
          p1: seg.p1,
        ));
      }
      if (segs.isNotEmpty) cubics.add(st.StrokeCubic(segs));
    }
    if (cubics.isEmpty) return null;
    return st.GlyphData(cubics: cubics, bounds: internal.bounds);
  }
}
