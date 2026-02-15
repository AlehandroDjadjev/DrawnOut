import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/developer_mode_provider.dart';

/// A wrapper widget that gates developer debug tools behind the
/// [DeveloperModeProvider] flag and [kDebugMode].
///
/// Usage:
/// ```dart
/// DeveloperDashboard(
///   child: myDebugPanelContent,
/// )
/// ```
///
/// On release builds the dashboard is always hidden.  In debug builds it
/// is only visible when the current user has `is_developer = true` in the
/// backend database.
class DeveloperDashboard extends StatelessWidget {
  /// The debug panel content to display when the dashboard is visible.
  final Widget child;

  /// Optional width constraint (defaults to 360 for side-panel usage).
  final double width;

  const DeveloperDashboard({
    super.key,
    required this.child,
    this.width = 360,
  });

  @override
  Widget build(BuildContext context) {
    // Always hidden in release builds
    if (!kDebugMode) return const SizedBox.shrink();

    final devMode = Provider.of<DeveloperModeProvider>(context);
    if (!devMode.isEnabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Dashboard header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              border: Border(
                bottom: BorderSide(
                  color: Colors.orange.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.developer_mode, size: 16, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  'Developer Dashboard',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.orange[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(child: child),
        ],
      ),
    );
  }
}
