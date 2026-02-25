import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/lesson_list_item.dart';
import '../services/app_config_service.dart';
import '../services/auth_service.dart';
import '../services/lesson_api_service.dart';
import '../ui/apple_ui.dart';

/// Apple-style lessons browser.
///
/// Pulls lessons from `GET /api/lessons/list/` and displays the backend
/// `progress_state` as a pill badge.
class LessonsPage extends StatefulWidget {
  final bool embedded;

  const LessonsPage({
    super.key,
    this.embedded = false,
  });

  @override
  State<LessonsPage> createState() => _LessonsPageState();
}

class _LessonsPageState extends State<LessonsPage> {
  bool _loading = true;
  String? _error;
  List<LessonListItem> _lessons = const [];
  String? _selectedSubject;
  String? _selectedDifficulty;
  bool _hasTokens = false;
  String _query = '';

  /// UI-only progress: once a lesson is clicked, show it as "In progress".
  ///
  /// This is intentionally local and ephemeral until backend completion
  /// tracking is wired up.
  final Set<int> _clickedLessonIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
    });
  }

  Future<void> _reload() async {
    final config = context.read<AppConfigService>();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final authService = AuthService(baseUrl: config.backendUrl);
      final hasTokens = await authService.hasTokens();

      final api = LessonApiService(baseUrl: config.backendUrl);
      api.onSessionExpired = () {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
      };

      final lessons = await api.listLessons(
        subject: _selectedSubject,
        difficulty: _selectedDifficulty,
      );

      if (!mounted) return;
      setState(() {
        _hasTokens = hasTokens;
        _lessons = lessons;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final query = _query.trim().toLowerCase();
    final lessonsToDisplay = query.isEmpty
        ? _lessons
        : _lessons
            .where((l) => l.title.toLowerCase().contains(query))
            .toList(growable: false);

    final subjects = _extractUnique(
      _lessons.map((l) => l.subject).whereType<String>(),
    );
    final difficulties = _extractUnique(
      _lessons.map((l) => l.difficulty).whereType<String>(),
    );

    final featuredPythagoras = _findFeaturedPythagoras(_lessons);

    final grouped = <String, List<LessonListItem>>{};
    for (final l in lessonsToDisplay) {
      final key = (l.subject == null || l.subject!.trim().isEmpty)
          ? 'Other'
          : l.subject!.trim();
      grouped.putIfAbsent(key, () => []).add(l);
    }

    final scrollView = CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _reload),
        if (!widget.embedded)
          CupertinoSliverNavigationBar(
            largeTitle: const Text('Lessons'),
            middle: const Text('Lessons'),
            border: null,
            backgroundColor:
                (isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7))
                    .withOpacity(0.85),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, widget.embedded ? 16 : 4, 20, 24),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pick a lesson. Every lesson shows its status.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.70),
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppleCard(
                      frosted: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: CupertinoSearchTextField(
                        placeholder: 'Search lessons',
                        onChanged: (v) => setState(() => _query = v),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!_loading)
                      _FiltersCard(
                        subjects: subjects,
                        difficulties: difficulties,
                        selectedSubject: _selectedSubject,
                        selectedDifficulty: _selectedDifficulty,
                        canClear: _selectedSubject != null ||
                            _selectedDifficulty != null ||
                            _query.trim().isNotEmpty,
                        onClear: () {
                          setState(() {
                            _selectedSubject = null;
                            _selectedDifficulty = null;
                            _query = '';
                          });
                          _reload();
                        },
                        onSubjectChanged: (v) {
                          setState(() => _selectedSubject = v);
                          _reload();
                        },
                        onDifficultyChanged: (v) {
                          setState(() => _selectedDifficulty = v);
                          _reload();
                        },
                      ),
                    const SizedBox(height: 12),
                    _FeaturedLessonCard(
                      title: featuredPythagoras?.title ?? 'Pythagorean Theorem',
                      subtitle: featuredPythagoras == null
                          ? 'Featured lesson'
                          : 'Featured lesson • ${featuredPythagoras.subject ?? 'mathematics'}',
                      onTap: () {
                        if (featuredPythagoras != null) {
                          _openLesson(featuredPythagoras);
                          return;
                        }
                        HapticFeedback.selectionClick();
                        Navigator.pushNamed(
                          context,
                          '/whiteboard',
                          arguments: {
                            'topic': 'Pythagorean Theorem',
                            'title': 'Pythagorean Theorem',
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!_hasTokens)
                      AppleCard(
                        frosted: true,
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.65),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Log in to track progress across devices. You can still browse lessons.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.75),
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      AppleErrorBanner(message: _error!),
                    ],
                    const SizedBox(height: 14),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 32),
                        child: Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                'Loading lessons…',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (lessonsToDisplay.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: AppleCard(
                          frosted: true,
                          child: Row(
                            children: [
                              Icon(
                                Icons.menu_book,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'No lessons found for these filters.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...grouped.entries.map((entry) {
                        final subject = entry.key;
                        final lessons = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppleSectionTitle(title: subject),
                              const SizedBox(height: 10),
                              ...lessons.map(
                                (lesson) => _LessonRow(
                                  lesson: lesson,
                                  progressState: _effectiveProgressState(lesson),
                                  onTap: () => _openLesson(lesson),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return scrollView;
    }

    return Scaffold(
      body: AppleBackground(child: scrollView),
    );
  }

  void _openLesson(LessonListItem lesson) {
    if (lesson.progressState != LessonProgressState.completed) {
      setState(() {
        _clickedLessonIds.add(lesson.id);
      });
    }
    HapticFeedback.selectionClick();
    Navigator.pushNamed(
      context,
      '/whiteboard',
      arguments: {
        'topic': lesson.title,
        'title': lesson.title,
        'lesson_id': lesson.id,
      },
    );
  }

  LessonProgressState _effectiveProgressState(LessonListItem lesson) {
    final api = lesson.progressState;
    if (api == LessonProgressState.completed) return api;
    if (api == LessonProgressState.inProgress) return api;
    return _clickedLessonIds.contains(lesson.id)
        ? LessonProgressState.inProgress
        : LessonProgressState.notStarted;
  }

  static List<String> _extractUnique(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final v = raw.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }
    out.sort();
    return out;
  }
}

class _FiltersCard extends StatelessWidget {
  final List<String> subjects;
  final List<String> difficulties;
  final String? selectedSubject;
  final String? selectedDifficulty;
  final bool canClear;
  final VoidCallback onClear;
  final ValueChanged<String?> onSubjectChanged;
  final ValueChanged<String?> onDifficultyChanged;

  const _FiltersCard({
    required this.subjects,
    required this.difficulties,
    required this.selectedSubject,
    required this.selectedDifficulty,
    required this.canClear,
    required this.onClear,
    required this.onSubjectChanged,
    required this.onDifficultyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppleSectionTitle(
            title: 'Filters',
            trailing: canClear
                ? TextButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          ApplePillRow(
            children: [
              _PillGroupLabel('Subject', theme: theme),
              ApplePillButton(
                label: 'All',
                selected: selectedSubject == null,
                onTap: () => onSubjectChanged(null),
                icon: Icons.grid_view_rounded,
              ),
              ...subjects.map(
                (s) => ApplePillButton(
                  label: s,
                  selected: selectedSubject == s,
                  onTap: () => onSubjectChanged(s),
                ),
              ),
              _PillGroupDivider(theme: theme),
              _PillGroupLabel('Difficulty', theme: theme),
              ApplePillButton(
                label: 'All',
                selected: selectedDifficulty == null,
                onTap: () => onDifficultyChanged(null),
                icon: Icons.tune_rounded,
              ),
              ...difficulties.map(
                (d) => ApplePillButton(
                  label: d,
                  selected: selectedDifficulty == d,
                  onTap: () => onDifficultyChanged(d),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

LessonListItem? _findFeaturedPythagoras(List<LessonListItem> lessons) {
  for (final l in lessons) {
    final t = l.title.toLowerCase();
    if (t.contains('pythag')) return l;
  }
  return null;
}

class _PillGroupDivider extends StatelessWidget {
  final ThemeData theme;

  const _PillGroupDivider({required this.theme});

  @override
  Widget build(BuildContext context) {
    final c = theme.colorScheme.onSurface.withOpacity(0.10);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 22,
        child: VerticalDivider(
          width: 14,
          thickness: 1,
          color: c,
        ),
      ),
    );
  }
}

class _PillGroupLabel extends StatelessWidget {
  final String text;
  final ThemeData theme;

  const _PillGroupLabel(this.text, {required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 2),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.65),
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _FeaturedLessonCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeaturedLessonCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppleCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5E5CE6), Color(0xFF64D2FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.change_history_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.70),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withOpacity(0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final LessonListItem lesson;
  final LessonProgressState progressState;
  final VoidCallback onTap;

  const _LessonRow({
    required this.lesson,
    required this.progressState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final subject = (lesson.subject == null || lesson.subject!.trim().isEmpty)
        ? 'Lesson'
        : lesson.subject!.trim();
    final difficulty =
        (lesson.difficulty == null || lesson.difficulty!.trim().isEmpty)
            ? null
            : lesson.difficulty!.trim();

    final accent = _accentForProgress(progressState, isDark: isDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppleCard(
        padding: EdgeInsets.zero,
        frosted: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _iconForSubject(subject),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                lesson.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              subject,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.70),
                              ),
                            ),
                            if (difficulty != null) ...[
                              const SizedBox(width: 8),
                              _difficultyPill(context, difficulty),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Status:',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.62),
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              progressState.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    Icons.chevron_right,
                    color: isDark
                        ? theme.colorScheme.onSurface.withOpacity(0.45)
                        : theme.colorScheme.onSurface.withOpacity(0.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconForSubject(String subject) {
    final s = subject.toLowerCase();
    if (s.contains('math')) return Icons.functions;
    if (s.contains('phys')) return Icons.speed;
    if (s.contains('bio')) return Icons.eco;
    if (s.contains('chem')) return Icons.science;
    return Icons.menu_book;
  }

  static Widget _difficultyPill(BuildContext context, String difficulty) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    switch (difficulty.toLowerCase()) {
      case 'beginner':
        color = const Color(0xFF1A7F37);
        break;
      case 'intermediate':
        color = const Color(0xFFB54708);
        break;
      case 'advanced':
        color = const Color(0xFFB42318);
        break;
      default:
        color = theme.colorScheme.onSurface.withOpacity(0.60);
    }

    final bg = isDark ? color.withOpacity(0.22) : color.withOpacity(0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Text(
        difficulty,
        style: theme.textTheme.labelMedium?.copyWith(
          color: isDark ? color.withOpacity(0.95) : color,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  static Color _accentForProgress(
    LessonProgressState state, {
    required bool isDark,
  }) {
    return switch (state) {
      LessonProgressState.notStarted =>
        (isDark ? const Color(0xFFB0B0B6) : const Color(0xFF6B7280)),
      LessonProgressState.inProgress =>
        (isDark ? const Color(0xFF7CC3FF) : const Color(0xFF0B63CE)),
      LessonProgressState.completed =>
        (isDark ? const Color(0xFF7FE3B1) : const Color(0xFF1A7F37)),
    };
  }
}

