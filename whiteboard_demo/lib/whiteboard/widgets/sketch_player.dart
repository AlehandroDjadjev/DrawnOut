import 'package:flutter/material.dart';
import '../core/stroke_plan.dart';
import '../core/placed_image.dart';
import '../painters/sketch_painter.dart';

/// Animated sketch player widget.
///
/// Plays a stroke plan animation over a specified duration,
/// optionally showing a raster image underlay.
class SketchPlayer extends StatefulWidget {
  final StrokePlan plan;
  final double totalSeconds;
  final double baseWidth;
  final double passOpacity;
  final int passes;
  final double jitterAmp;
  final double jitterFreq;
  final bool showRasterUnderlay;
  final PlacedImage? raster;

  const SketchPlayer({
    super.key,
    required this.plan,
    required this.totalSeconds,
    this.baseWidth = 2.5,
    this.passOpacity = 0.8,
    this.passes = 2,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.02,
    this.showRasterUnderlay = true,
    this.raster,
  });

  @override
  State<SketchPlayer> createState() => _SketchPlayerState();
}

class _SketchPlayerState extends State<SketchPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Path _fullPath;
  late double _totalLen;

  @override
  void initState() {
    super.initState();
    _fullPath = widget.plan.toPath();
    _totalLen = _computeTotalLen(_fullPath);
    _anim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.totalSeconds * 1000).round()),
    )
      ..addListener(() => setState(() {}))
      ..forward();
  }

  @override
  void didUpdateWidget(covariant SketchPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan ||
        oldWidget.totalSeconds != widget.totalSeconds) {
      _fullPath = widget.plan.toPath();
      _totalLen = _computeTotalLen(_fullPath);
      _anim.duration =
          Duration(milliseconds: (widget.totalSeconds * 1000).round());
      _anim
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressLen = (_totalLen * _anim.value).clamp(0.0, _totalLen);
    final partial = _extractPartialPath(_fullPath, progressLen);

    return CustomPaint(
      painter: SketchPainter(
        partialWorldPath: partial,
        raster: widget.showRasterUnderlay ? widget.raster : null,
        passes: widget.passes,
        passOpacity: widget.passOpacity,
        baseWidth: widget.baseWidth,
        jitterAmp: widget.jitterAmp,
        jitterFreq: widget.jitterFreq,
      ),
      isComplex: true,
    );
  }

  double _computeTotalLen(Path p) {
    double length = 0.0;
    for (final m in p.computeMetrics()) {
      length += m.length;
    }
    return length;
  }

  Path _extractPartialPath(Path p, double targetLen) {
    final out = Path();
    double acc = 0.0;
    for (final m in p.computeMetrics()) {
      if (acc >= targetLen) break;
      final remain = targetLen - acc;
      final take = remain >= m.length ? m.length : remain;
      if (take > 0) {
        out.addPath(m.extractPath(0, take), Offset.zero);
        acc += take;
      }
    }
    return out;
  }
}
