import 'package:flutter/material.dart';
import '../controllers/timeline_playback_controller.dart';

/// Bottom bar with play/pause/restart controls and a timeline scrubber with
/// segment markers.  Listens to [TimelinePlaybackController] and rebuilds
/// automatically.
class LessonPlaybackBar extends StatelessWidget {
  final TimelinePlaybackController controller;

  const LessonPlaybackBar({super.key, required this.controller});

  // ── helpers ────────────────────────────────────────────────────────────
  static String _fmt(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds.truncate() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int _closestSegmentIndex(double fraction) {
    final timeline = controller.timeline;
    if (timeline == null || timeline.segments.isEmpty) return 0;
    final target = fraction * controller.totalDuration;
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < timeline.segments.length; i++) {
      final dist = (timeline.segments[i].startTime - target).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final timeline = controller.timeline;
        if (timeline == null) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isActive = controller.isActive; // playing and not paused
        final progress = controller.progress;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Timeline scrubber ─────────────────────────────────
                Semantics(
                  label:
                      'Lesson playback progress: ${(progress * 100).round()} percent',
                  child: SizedBox(
                    height: 28,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) {
                            final frac =
                                (d.localPosition.dx / width).clamp(0.0, 1.0);
                            controller
                                .seekToSegment(_closestSegmentIndex(frac));
                          },
                          onHorizontalDragUpdate: (d) {
                            final frac =
                                (d.localPosition.dx / width).clamp(0.0, 1.0);
                            controller
                                .seekToSegment(_closestSegmentIndex(frac));
                          },
                          child: CustomPaint(
                            size: Size(width, 28),
                            painter: _ScrubberPainter(
                              progress: progress,
                              segments: timeline.segments,
                              totalDuration: controller.totalDuration,
                              activeColor: colorScheme.primary,
                              trackColor:
                                  colorScheme.onSurface.withOpacity(0.12),
                              markerColor:
                                  colorScheme.onSurface.withOpacity(0.25),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // ── Controls row ──────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    children: [
                      // Restart
                      IconButton(
                        icon: const Icon(Icons.replay, size: 22),
                        tooltip: 'Restart lesson',
                        onPressed: () => controller.restart(),
                      ),
                      // Play / Pause
                      IconButton(
                        icon: Icon(
                          isActive
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 32,
                          color: colorScheme.primary,
                        ),
                        tooltip: isActive ? 'Pause' : 'Play',
                        onPressed: () {
                          if (isActive) {
                            controller.pause();
                          } else {
                            controller.play();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      // Time display
                      Text(
                        '${_fmt(controller.currentTime)} / ${_fmt(controller.totalDuration)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      // Segment indicator
                      Text(
                        'Segment ${controller.currentSegmentIndex + 1} / ${controller.segmentCount}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Custom painter for scrubber with segment markers ─────────────────────

class _ScrubberPainter extends CustomPainter {
  final double progress;
  final List segments;
  final double totalDuration;
  final Color activeColor;
  final Color trackColor;
  final Color markerColor;

  _ScrubberPainter({
    required this.progress,
    required this.segments,
    required this.totalDuration,
    required this.activeColor,
    required this.trackColor,
    required this.markerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height / 2;
    const trackHeight = 4.0;
    final trackRadius = Radius.circular(trackHeight / 2);

    // Background track
    canvas.drawRRect(
      RRect.fromLTRBR(
          0, trackY - trackHeight / 2, size.width, trackY + trackHeight / 2, trackRadius),
      Paint()..color = trackColor,
    );

    // Active track
    final activeWidth = size.width * progress;
    if (activeWidth > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
            0, trackY - trackHeight / 2, activeWidth, trackY + trackHeight / 2, trackRadius),
        Paint()..color = activeColor,
      );
    }

    // Segment markers (small vertical ticks)
    if (totalDuration > 0) {
      final markerPaint = Paint()
        ..color = markerColor
        ..strokeWidth = 1.5;
      for (final seg in segments) {
        final frac = seg.startTime / totalDuration;
        if (frac <= 0.0 || frac >= 1.0) continue;
        final x = frac * size.width;
        canvas.drawLine(
          Offset(x, trackY - 6),
          Offset(x, trackY + 6),
          markerPaint,
        );
      }
    }

    // Thumb
    if (activeWidth > 0) {
      canvas.drawCircle(
        Offset(activeWidth.clamp(6.0, size.width - 6.0), trackY),
        6,
        Paint()..color = activeColor,
      );
      canvas.drawCircle(
        Offset(activeWidth.clamp(6.0, size.width - 6.0), trackY),
        3,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubberPainter old) =>
      old.progress != progress ||
      old.totalDuration != totalDuration ||
      old.segments.length != segments.length;
}
