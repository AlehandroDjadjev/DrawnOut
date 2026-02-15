import 'package:flutter/material.dart';

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
class LessonsPage extends StatelessWidget {
  const LessonsPage({super.key});

  // Sample lessons - in production these would come from backend
  static const List<Lesson> _lessons = [
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // Group lessons by topic
    final lessonsByTopic = <String, List<Lesson>>{};
    for (final lesson in _lessons) {
      lessonsByTopic.putIfAbsent(lesson.topic, () => []).add(lesson);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lessons'),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        foregroundColor: colorScheme.primary,
        elevation: 1,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lessonsByTopic.length,
        itemBuilder: (context, index) {
          final topic = lessonsByTopic.keys.elementAt(index);
          final lessons = lessonsByTopic[topic]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  topic,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              ...lessons.map((lesson) => _LessonCard(
                lesson: lesson,
                onTap: () => _startLesson(context, lesson),
              )),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  void _startLesson(BuildContext context, Lesson lesson) {
    Navigator.pushNamed(
      context,
      '/whiteboard',
      arguments: {
        'topic': lesson.title,
        'title': lesson.title,
      },
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
