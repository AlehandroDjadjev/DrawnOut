import 'package:flutter/material.dart';
import 'whiteboard_page.dart';
import '../ui/apple_ui.dart';

/// Available lesson data
class Lesson {
  final int id;
  final String title;
  final String description;
  final String topic;
  final String difficulty;
  final int? sessionId;
  final Duration estimatedDuration;
  final IconData icon;

  const Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.topic,
    this.difficulty = 'Beginner',
    this.sessionId,
    this.estimatedDuration = const Duration(minutes: 5),
    this.icon = Icons.school,
  });
}

/// Page displaying available lessons for selection
class LessonsPage extends StatefulWidget {
  const LessonsPage({super.key});

  @override
  State<LessonsPage> createState() => _LessonsPageState();

  // Sample lessons - in production these would come from backend
  static const List<Lesson> sampleLessons = [
    Lesson(
      id: 1,
      title: 'Pythagoras Theorem',
      description: 'Explore the relationship between the sides of a right-angled triangle.',
      topic: 'Mathematics',
      difficulty: 'Beginner',
      sessionId: 1,
      estimatedDuration: Duration(minutes: 8),
      icon: Icons.square_foot,
    ),
    Lesson(
      id: 2,
      title: 'Quadratic Equations',
      description: 'Learn to solve equations of the form ax² + bx + c = 0.',
      topic: 'Mathematics',
      difficulty: 'Intermediate',
      sessionId: 2,
      estimatedDuration: Duration(minutes: 12),
      icon: Icons.functions,
    ),
    Lesson(
      id: 3,
      title: 'Newton\'s Laws of Motion',
      description: 'Understand the fundamental laws governing object movement.',
      topic: 'Physics',
      difficulty: 'Beginner',
      sessionId: 3,
      estimatedDuration: Duration(minutes: 10),
      icon: Icons.speed,
    ),
    Lesson(
      id: 4,
      title: 'Photosynthesis',
      description: 'Discover how plants convert sunlight into energy.',
      topic: 'Biology',
      difficulty: 'Beginner',
      sessionId: 4,
      estimatedDuration: Duration(minutes: 7),
      icon: Icons.eco,
    ),
  ];
}

class _LessonsPageState extends State<LessonsPage> {
  static const String _all = 'All';

  String _subject = _all;
  String _difficulty = _all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final allLessons = LessonsPage.sampleLessons;
    final subjects = <String>{_all, ...allLessons.map((l) => l.topic)}.toList()..sort();
    final difficulties = <String>{_all, ...allLessons.map((l) => l.difficulty)}.toList()..sort();

    final filtered = allLessons.where((l) {
      final subjectOk = _subject == _all || l.topic == _subject;
      final difficultyOk = _difficulty == _all || l.difficulty == _difficulty;
      return subjectOk && difficultyOk;
    }).toList();

    // Group lessons by topic (after filtering)
    final lessonsByTopic = <String, List<Lesson>>{};
    for (final lesson in filtered) {
      lessonsByTopic.putIfAbsent(lesson.topic, () => []).add(lesson);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lessons'),
        centerTitle: true,
      ),
      body: AppleBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          children: [
            const AppleHeader(
              title: 'Choose a lesson',
              subtitle: 'Filter by subject and difficulty, then jump in.',
            ),
            const SizedBox(height: 14),
            AppleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppleSectionTitle(title: 'Filters'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _subject,
                          decoration: appleFieldDecoration(
                            context,
                            hintText: 'Subject',
                            icon: Icons.category_outlined,
                          ),
                          items: subjects
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _subject = v ?? _all),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _difficulty,
                          decoration: appleFieldDecoration(
                            context,
                            hintText: 'Difficulty',
                            icon: Icons.tune,
                          ),
                          items: difficulties
                              .map(
                                (d) => DropdownMenuItem(
                                  value: d,
                                  child: Text(d),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _difficulty = v ?? _all),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_subject != _all || _difficulty != _all)
                    TextButton(
                      onPressed: () => setState(() {
                        _subject = _all;
                        _difficulty = _all;
                      }),
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (filtered.isEmpty)
              AppleCard(
                child: Text(
                  'No lessons match your filters.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...lessonsByTopic.entries.expand((entry) {
                final topic = entry.key;
                final lessons = entry.value;
                return [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      topic,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  ...lessons.map(
                    (lesson) => _LessonCard(
                      lesson: lesson,
                      onTap: () => _startLesson(context, lesson),
                    ),
                  ),
                  const SizedBox(height: 4),
                ];
              }),
          ],
        ),
      ),
    );
  }

  void _startLesson(BuildContext context, Lesson lesson) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhiteboardPage(
          lessonContext: LessonContext(
            lessonId: lesson.id,
            sessionId: lesson.sessionId,
            title: lesson.title,
            topic: lesson.topic,
          ),
          onLessonComplete: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Completed: ${lesson.title}'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final VoidCallback onTap;

  const _LessonCard({
    required this.lesson,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    Color difficultyColor;
    switch (lesson.difficulty) {
      case 'Beginner':
        difficultyColor = Colors.green;
        break;
      case 'Intermediate':
        difficultyColor = Colors.orange;
        break;
      case 'Advanced':
        difficultyColor = Colors.red;
        break;
      default:
        difficultyColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? Colors.grey[850] : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  lesson.icon,
                  color: colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lesson.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: difficultyColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lesson.difficulty,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: difficultyColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lesson.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${lesson.estimatedDuration.inMinutes} min',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
