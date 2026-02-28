import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppleBackground extends StatelessWidget {
  final Widget child;

  const AppleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // iOS-like grouped background.
    final base = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final tint = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: base,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(tint.withOpacity(isDark ? 0.10 : 0.08), base),
            base,
          ],
        ),
      ),
      child: child,
    );
  }
}

class AppleCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool frosted;
  final double blurSigma;

  const AppleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.frosted = false,
    this.blurSigma = 14,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    final borderColor = (isDark ? Colors.white : Colors.black).withOpacity(0.06);

    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: frosted
            ? surface.withOpacity(isDark ? 0.72 : 0.86)
            : surface,
        gradient: frosted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  surface.withOpacity(isDark ? 0.78 : 0.92),
                  surface.withOpacity(isDark ? 0.60 : 0.80),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: child,
    );

    if (!frosted) return card;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: card,
      ),
    );
  }
}

class AppleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AppleHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.70),
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

InputDecoration appleFieldDecoration(
  BuildContext context, {
  required String hintText,
  IconData? icon,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  final fill = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

  return InputDecoration(
    hintText: hintText,
    prefixIcon: icon == null
        ? null
        : Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.65)),
    filled: true,
    fillColor: fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: theme.colorScheme.primary.withOpacity(0.55),
        width: 1.5,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}

class ApplePrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const ApplePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}

class AppleErrorBanner extends StatelessWidget {
  final String message;

  const AppleErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF3A1E1E) : const Color(0xFFFFF1F1);
    final fg = isDark ? const Color(0xFFFFB4B4) : const Color(0xFFB42318);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: fg, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: fg, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class AppleSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppleSectionTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class ApplePillButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool haptics;

  const ApplePillButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.haptics = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final unselectedBg =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final selectedBase = theme.colorScheme.primary;
    final selectedBg = Color.alphaBlend(
      selectedBase.withOpacity(isDark ? 0.30 : 0.16),
      unselectedBg,
    );

    final border = selected
        ? theme.colorScheme.primary.withOpacity(0.34)
        : theme.colorScheme.onSurface.withOpacity(0.10);

    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withOpacity(isDark ? 0.85 : 0.75);

    return AnimatedScale(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      scale: selected ? 1.02 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      selectedBase.withOpacity(isDark ? 0.34 : 0.18),
                      selectedBg,
                    ),
                    selectedBg,
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.25)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap == null
                ? null
                : () {
                    if (haptics) {
                      HapticFeedback.selectionClick();
                    }
                    onTap?.call();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ApplePillRow extends StatelessWidget {
  final List<Widget> children;
  final bool showTrack;
  final EdgeInsetsGeometry contentPadding;
  final double spacing;

  const ApplePillRow({
    super.key,
    required this.children,
    this.showTrack = true,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final trackBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final trackBorder =
        (isDark ? Colors.white : Colors.black).withOpacity(0.08);

    final scroller = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: contentPadding,
        child: Row(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i != 0) SizedBox(width: spacing),
              children[i],
            ],
          ],
        ),
      ),
    );

    if (!showTrack) return scroller;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: trackBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: trackBorder),
          boxShadow: isDark
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: scroller,
      ),
    );
  }
}
