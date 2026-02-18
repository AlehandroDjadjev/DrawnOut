import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';

/// Displays the user's past lesson sessions with the option to rewatch
/// completed lessons that have a saved timeline.
class LessonHistoryPage extends StatefulWidget {
  const LessonHistoryPage({super.key});

  @override
  State<LessonHistoryPage> createState() => _LessonHistoryPageState();
}

class _LessonHistoryPageState extends State<LessonHistoryPage> {
  List<dynamic> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final base = (dotenv.env['API_URL'] ?? 'http://127.0.0.1:8000').trim();
      final authService = AuthService(baseUrl: base);
      final resp = await authService.authenticatedGet('$base/api/lessons/history/');

      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() {
          _sessions = jsonDecode(resp.body) as List<dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load history (${resp.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to server';
        _loading = false;
      });
    }
  }

  void _rewatch(Map<String, dynamic> session) {
    Navigator.pushNamed(
      context,
      '/whiteboard',
      arguments: {
        'session_id': session['id'],
        'title': session['topic'],
        'rewatch': true,
      },
    );
  }

  static String _fmtDuration(double? seconds) {
    if (seconds == null) return '--:--';
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds.truncate() % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lesson History'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: colorScheme.error)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _fetchHistory,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No lessons yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Start a lesson and it will appear here',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final s = _sessions[index] as Map<String, dynamic>;
                          return _SessionCard(
                            topic: (s['topic'] ?? '') as String,
                            date: _fmtDate(s['created_at'] as String?),
                            duration: _fmtDuration(
                              (s['total_duration'] as num?)?.toDouble(),
                            ),
                            segmentCount: (s['segment_count'] as int?) ?? 0,
                            isCompleted: (s['is_completed'] as bool?) ?? false,
                            hasTimeline: s['timeline_id'] != null,
                            onRewatch: s['timeline_id'] != null
                                ? () => _rewatch(s)
                                : null,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final String topic;
  final String date;
  final String duration;
  final int segmentCount;
  final bool isCompleted;
  final bool hasTimeline;
  final VoidCallback? onRewatch;

  const _SessionCard({
    required this.topic,
    required this.date,
    required this.duration,
    required this.segmentCount,
    required this.isCompleted,
    required this.hasTimeline,
    this.onRewatch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.school, color: colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? Colors.green.withOpacity(0.12)
                        : Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isCompleted ? 'Completed' : 'In progress',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isCompleted ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Stats row
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(duration,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(width: 16),
                Icon(Icons.view_carousel_outlined,
                    size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text('$segmentCount segments',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const Spacer(),
                // Rewatch button
                if (hasTimeline)
                  FilledButton.tonalIcon(
                    onPressed: onRewatch,
                    icon: const Icon(Icons.replay, size: 16),
                    label: const Text('Rewatch'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
