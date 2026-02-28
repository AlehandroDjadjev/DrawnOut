import 'package:flutter/material.dart';
import '../../models/drawable_stroke.dart';
import '../painters/whiteboard_painter.dart';
import '../services/backend_stroke_service.dart';

/// Plays back a backend-pipeline image as an animated hand-drawn sketch.
///
/// Accepts the raw `strokes` JSON map returned by the lesson pipeline
/// (the `metadata.strokes` field of a resolved image action) and renders
/// it using the full [WhiteboardPainter] engine — exactly the same visual
/// quality as DrawnOutWhiteboard.
///
/// Usage:
/// ```dart
/// BackendImagePlayer(
///   strokesJson: resolvedImage.metadata?['strokes'] as Map<String, dynamic>,
///   isPaused: _isPaused,
/// )
/// ```
class BackendImagePlayer extends StatefulWidget {
  /// The raw strokes payload from the backend pipeline.
  /// Must have keys: `vector_format`, `width`, `height`, `strokes`.
  final Map<String, dynamic>? strokesJson;

  /// Freeze the animation at the current frame when true.
  final bool isPaused;

  /// Label used to group/identify the strokes (for debug).
  final String label;

  /// Speed multiplier: values > 1 draw faster, < 1 draw slower.
  final double speedMultiplier;

  /// Base pen width in board pixels.
  final double basePenWidth;

  /// Board size in virtual world pixels (2000×2000 matches DrawnOutWhiteboard).
  final double boardSize;

  /// Whether to use the per-stroke colors from the backend.
  /// Set to false to render everything in [monochromeColor].
  final bool useStrokeColors;

  /// Color to use when [useStrokeColors] is false.
  final Color monochromeColor;

  const BackendImagePlayer({
    super.key,
    required this.strokesJson,
    this.isPaused = false,
    this.label = 'backend_image',
    this.speedMultiplier = 1.0,
    this.basePenWidth = 4.0,
    this.boardSize = 2000.0,
    this.useStrokeColors = false,
    this.monochromeColor = Colors.black,
  });

  @override
  State<BackendImagePlayer> createState() => _BackendImagePlayerState();
}

class _BackendImagePlayerState extends State<BackendImagePlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  List<DrawableStroke> _strokes = const [];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() => setState(() {}));

    _buildStrokes(widget.strokesJson);
  }

  @override
  void didUpdateWidget(covariant BackendImagePlayer old) {
    super.didUpdateWidget(old);

    if (old.strokesJson != widget.strokesJson) {
      _buildStrokes(widget.strokesJson);
    }

    if (old.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        _anim.stop();
      } else if (!_anim.isCompleted) {
        _anim.forward();
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _buildStrokes(Map<String, dynamic>? json) {
    if (json == null) {
      setState(() {
        _strokes = const [];
      });
      return;
    }

    final parsed = BackendStrokeService.parseJson(json);
    if (parsed == null) {
      setState(() {
        _strokes = const [];
      });
      return;
    }

    final drawable = BackendStrokeService.buildDrawableStrokes(
      strokes: parsed.strokes,
      srcWidth: parsed.srcWidth,
      srcHeight: parsed.srcHeight,
      origin: Offset.zero, // centered on board
      label: widget.label,
    );

    final rawTotal =
        drawable.fold<double>(0.0, (s, d) => s + d.timeWeight);
    final totalSec = rawTotal / widget.speedMultiplier.clamp(0.1, 10.0);

    _anim.duration =
        Duration(milliseconds: (totalSec * 1000).clamp(100, 60000).round());

    setState(() {
      _strokes = drawable;
    });

    if (!widget.isPaused) {
      _anim
        ..reset()
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_strokes.isEmpty) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: WhiteboardPainter(
        staticStrokes: const [],
        animStrokes: _strokes,
        animationT: _anim.value,
        basePenWidth: widget.basePenWidth,
        stepMode: false,
        stepStrokeCount: 0,
        boardWidth: widget.boardSize,
        boardHeight: widget.boardSize,
        strokeColor: widget.monochromeColor,
        useStrokeColors: widget.useStrokeColors,
      ),
      isComplex: true,
      child: const SizedBox.expand(),
    );
  }
}
