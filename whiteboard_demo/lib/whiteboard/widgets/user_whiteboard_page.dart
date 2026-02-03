import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/core.dart';
import '../painters/painters.dart';

/// Playback state for the whiteboard animation.
enum PlaybackState { stopped, playing, paused }

/// Clean, user-facing whiteboard page with minimal UI.
///
/// Features:
/// - Full-screen canvas
/// - Play/pause/progress controls
/// - Mobile-responsive layout
/// - Touch gesture support (pinch-zoom, pan)
/// - Developer mode toggle
class UserWhiteboardPage extends StatefulWidget {
  /// The stroke plan to animate.
  final StrokePlan? plan;

  /// Total animation duration in seconds.
  final double totalSeconds;

  /// Committed vector objects to display.
  final List<VectorObject> committedObjects;

  /// Optional raster image underlay.
  final PlacedImage? raster;

  /// Whether to show the raster underlay during animation.
  final bool showRasterUnderlay;

  /// Stroke style parameters.
  final double baseWidth;
  final double passOpacity;
  final int passes;
  final double jitterAmp;
  final double jitterFreq;

  /// Callback when user wants to switch to developer mode.
  final VoidCallback? onSwitchToDeveloperMode;

  /// Callback when animation completes.
  final VoidCallback? onAnimationComplete;

  const UserWhiteboardPage({
    super.key,
    this.plan,
    this.totalSeconds = 10.0,
    this.committedObjects = const [],
    this.raster,
    this.showRasterUnderlay = false,
    this.baseWidth = 2.5,
    this.passOpacity = 0.8,
    this.passes = 2,
    this.jitterAmp = 0.9,
    this.jitterFreq = 0.02,
    this.onSwitchToDeveloperMode,
    this.onAnimationComplete,
  });

  @override
  State<UserWhiteboardPage> createState() => _UserWhiteboardPageState();
}

class _UserWhiteboardPageState extends State<UserWhiteboardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  PlaybackState _playbackState = PlaybackState.stopped;

  // Transform state for pan/zoom gestures
  final TransformationController _transformController =
      TransformationController();
  double _scale = 1.0;

  // UI visibility
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  // Full path and length for progress calculation
  Path? _fullPath;
  double _totalLength = 0;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _computePathMetrics();
    _startHideControlsTimer();
  }

  void _initAnimation() {
    _animController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.totalSeconds * 1000).round()),
    );
    _animController.addListener(() {
      setState(() {});
    });
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _playbackState = PlaybackState.stopped);
        widget.onAnimationComplete?.call();
      }
    });
  }

  void _computePathMetrics() {
    if (widget.plan == null || widget.plan!.isEmpty) {
      _fullPath = null;
      _totalLength = 0;
      return;
    }
    _fullPath = widget.plan!.toPath();
    _totalLength = 0;
    for (final m in _fullPath!.computeMetrics()) {
      _totalLength += m.length;
    }
  }

  @override
  void didUpdateWidget(covariant UserWhiteboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan ||
        oldWidget.totalSeconds != widget.totalSeconds) {
      _computePathMetrics();
      _animController.duration =
          Duration(milliseconds: (widget.totalSeconds * 1000).round());
      if (_playbackState == PlaybackState.playing) {
        _animController
          ..reset()
          ..forward();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _transformController.dispose();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _playbackState == PlaybackState.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls() {
    setState(() => _controlsVisible = true);
    _startHideControlsTimer();
  }

  void _togglePlayPause() {
    HapticFeedback.lightImpact();
    setState(() {
      switch (_playbackState) {
        case PlaybackState.stopped:
          _playbackState = PlaybackState.playing;
          _animController
            ..reset()
            ..forward();
          _startHideControlsTimer();
          break;
        case PlaybackState.playing:
          _playbackState = PlaybackState.paused;
          _animController.stop();
          _hideControlsTimer?.cancel();
          break;
        case PlaybackState.paused:
          _playbackState = PlaybackState.playing;
          _animController.forward();
          _startHideControlsTimer();
          break;
      }
    });
  }

  void _restart() {
    HapticFeedback.lightImpact();
    setState(() {
      _playbackState = PlaybackState.playing;
      _animController
        ..reset()
        ..forward();
      _startHideControlsTimer();
    });
  }

  void _seekTo(double value) {
    _animController.value = value;
    if (_playbackState == PlaybackState.stopped && value > 0) {
      setState(() => _playbackState = PlaybackState.paused);
    }
  }

  void _resetView() {
    HapticFeedback.lightImpact();
    _transformController.value = Matrix4.identity();
    setState(() {
      _scale = 1.0;
    });
  }

  Path _extractPartialPath(Path fullPath, double targetLen) {
    final out = Path();
    double acc = 0.0;
    for (final m in fullPath.computeMetrics()) {
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

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.shortestSide < 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: _showControls,
        child: Stack(
          children: [
            // Main canvas with gestures
            Positioned.fill(
              child: _buildInteractiveCanvas(),
            ),

            // Controls overlay
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Stack(
                  children: [
                    // Top bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildTopBar(context),
                    ),

                    // Bottom controls
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: _buildBottomControls(
                        context,
                        isLandscape: isLandscape,
                        isSmallScreen: isSmallScreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Loading indicator
            if (widget.plan == null && widget.committedObjects.isEmpty)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.draw_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No content to display',
                      style: TextStyle(color: Colors.grey, fontSize: 18),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveCanvas() {
    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 4.0,
      onInteractionUpdate: (details) {
        setState(() {
          _scale = _transformController.value.getMaxScaleOnAxis();
        });
      },
      child: _buildCanvas(),
    );
  }

  Widget _buildCanvas() {
    // Calculate partial path for current progress
    Path partialPath = Path();
    if (_fullPath != null && _totalLength > 0) {
      final progressLen =
          (_totalLength * _animController.value).clamp(0.0, _totalLength);
      partialPath = _extractPartialPath(_fullPath!, progressLen);
    }

    return Stack(
      children: [
        // Base sketch or raster
        Positioned.fill(
          child: widget.plan != null
              ? CustomPaint(
                  painter: SketchPainter(
                    partialWorldPath: partialPath,
                    raster: widget.showRasterUnderlay ? widget.raster : null,
                    passes: widget.passes,
                    passOpacity: widget.passOpacity,
                    baseWidth: widget.baseWidth,
                    jitterAmp: widget.jitterAmp,
                    jitterFreq: widget.jitterFreq,
                  ),
                  isComplex: true,
                )
              : CustomPaint(
                  painter: RasterOnlyPainter(raster: widget.raster),
                ),
        ),

        // Committed objects layer
        if (widget.committedObjects.isNotEmpty)
          Positioned.fill(
            child: CustomPaint(
              painter: CommittedPainter(widget.committedObjects),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              tooltip: 'Back',
            ),
            const Spacer(),

            // Zoom indicator
            if (_scale != 1.0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${(_scale * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),

            // Reset view button
            if (_scale != 1.0) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _resetView,
                icon: const Icon(Icons.fit_screen, color: Colors.white),
                tooltip: 'Reset view',
              ),
            ],

            // Developer mode button
            if (widget.onSwitchToDeveloperMode != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onSwitchToDeveloperMode?.call();
                },
                icon: const Icon(Icons.code, color: Colors.white),
                tooltip: 'Developer mode',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls(
    BuildContext context, {
    required bool isLandscape,
    required bool isSmallScreen,
  }) {
    final hasContent = widget.plan != null || widget.committedObjects.isNotEmpty;

    return SafeArea(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 16 : 32,
          vertical: isSmallScreen ? 12 : 20,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.5),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            if (hasContent && widget.plan != null) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white30,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  trackHeight: isSmallScreen ? 3 : 4,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: isSmallScreen ? 6 : 8,
                  ),
                ),
                child: Slider(
                  value: _animController.value,
                  onChanged: _seekTo,
                  onChangeStart: (_) {
                    if (_playbackState == PlaybackState.playing) {
                      _animController.stop();
                    }
                  },
                  onChangeEnd: (_) {
                    if (_playbackState == PlaybackState.playing) {
                      _animController.forward();
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Time and controls row
            if (hasContent)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Current time
                  if (widget.plan != null)
                    SizedBox(
                      width: 50,
                      child: Text(
                        _formatTime(
                            (_animController.value * widget.totalSeconds)
                                .round()),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const Spacer(),

                  // Restart button
                  if (widget.plan != null)
                    _buildControlButton(
                      icon: Icons.replay,
                      onPressed: _restart,
                      size: isSmallScreen ? 40 : 48,
                    ),

                  SizedBox(width: isSmallScreen ? 16 : 24),

                  // Play/Pause button
                  if (widget.plan != null)
                    _buildControlButton(
                      icon: _playbackState == PlaybackState.playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      onPressed: _togglePlayPause,
                      size: isSmallScreen ? 56 : 64,
                      isPrimary: true,
                    ),

                  const Spacer(),

                  // Total time
                  if (widget.plan != null)
                    SizedBox(
                      width: 50,
                      child: Text(
                        _formatTime(widget.totalSeconds.round()),
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required double size,
    bool isPrimary = false,
  }) {
    return Material(
      color: isPrimary ? Colors.white : Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isPrimary ? Colors.black : Colors.white,
            size: size * 0.5,
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
