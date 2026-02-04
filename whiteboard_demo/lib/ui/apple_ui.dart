import 'package:flutter/material.dart';

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

  const AppleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
        ),
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
