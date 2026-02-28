import 'dart:ui';

import 'package:flutter/material.dart';
import '../models/lesson_list_item.dart';

class LessonProgressBadge extends StatelessWidget {
  final LessonProgressState state;

  const LessonProgressBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final base = switch (state) {
      LessonProgressState.notStarted =>
        (isDark ? const Color(0xFFB0B0B6) : const Color(0xFF6B7280)),
      LessonProgressState.inProgress =>
        (isDark ? const Color(0xFF7CC3FF) : const Color(0xFF0B63CE)),
      LessonProgressState.completed =>
        (isDark ? const Color(0xFF7FE3B1) : const Color(0xFF1A7F37)),
    };

    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final bg = Color.alphaBlend(
      base.withOpacity(isDark ? 0.18 : 0.10),
      surface,
    );

    final border = base.withOpacity(isDark ? 0.26 : 0.22);
    final fg =
        isDark ? Color.alphaBlend(base.withOpacity(0.90), Colors.white) : base;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg.withOpacity(isDark ? 0.78 : 0.92),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                  base.withOpacity(isDark ? 0.16 : 0.10),
                  bg,
                ),
                bg,
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: base.withOpacity(0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state == LessonProgressState.inProgress) ...[
                _PulsingDot(color: fg),
                const SizedBox(width: 8),
              ] else ...[
                Icon(state.icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                state.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final scale = 0.92 + (0.16 * t);
        final opacity = 0.55 + (0.45 * t);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: widget.color.withOpacity(opacity),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.22),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
