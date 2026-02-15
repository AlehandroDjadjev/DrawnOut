import 'dart:async';
import 'package:flutter/material.dart';

/// Full-screen overlay shown when a lesson finishes playback.
///
/// Displays an animated checkmark, lesson stats, and buttons for replay or
/// navigation back to lessons.
class LessonCompletionOverlay extends StatefulWidget {
  final String? lessonTitle;
  final int segmentsCompleted;
  final double totalDurationSeconds;
  final VoidCallback onReplay;
  final VoidCallback onExit;

  /// Auto-dismiss after this duration if no user interaction. Null = no auto-dismiss.
  final Duration autoDismissAfter;

  const LessonCompletionOverlay({
    super.key,
    this.lessonTitle,
    required this.segmentsCompleted,
    required this.totalDurationSeconds,
    required this.onReplay,
    required this.onExit,
    this.autoDismissAfter = const Duration(seconds: 12),
  });

  @override
  State<LessonCompletionOverlay> createState() =>
      _LessonCompletionOverlayState();
}

class _LessonCompletionOverlayState extends State<LessonCompletionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();

    _autoDismiss = Timer(widget.autoDismissAfter, () {
      if (mounted) widget.onExit();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  static String _fmtDuration(double seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds.truncate() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.black54,
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated checkmark
                ExcludeSemantics(
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green.withOpacity(0.12),
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        size: 56,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Semantics(
                  header: true,
                  child: Text(
                    'Lesson Complete!',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.lessonTitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.lessonTitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 24),

                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatChip(
                      icon: Icons.view_carousel,
                      label: '${widget.segmentsCompleted} segments',
                    ),
                    const SizedBox(width: 16),
                    _StatChip(
                      icon: Icons.timer_outlined,
                      label: _fmtDuration(widget.totalDurationSeconds),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        _autoDismiss?.cancel();
                        widget.onReplay();
                      },
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Replay'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: () {
                        _autoDismiss?.cancel();
                        widget.onExit();
                      },
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back to Lessons'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
