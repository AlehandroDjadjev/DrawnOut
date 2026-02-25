import 'package:flutter/material.dart';

enum LessonProgressState {
  notStarted,
  inProgress,
  completed;

  static LessonProgressState fromApi(String? value) {
    switch (value) {
      case 'completed':
        return LessonProgressState.completed;
      case 'in_progress':
        return LessonProgressState.inProgress;
      case 'not_started':
      case null:
      case '':
        return LessonProgressState.notStarted;
      default:
        return LessonProgressState.notStarted;
    }
  }

  String get apiValue {
    switch (this) {
      case LessonProgressState.notStarted:
        return 'not_started';
      case LessonProgressState.inProgress:
        return 'in_progress';
      case LessonProgressState.completed:
        return 'completed';
    }
  }

  String get label {
    switch (this) {
      case LessonProgressState.notStarted:
        return 'Not started';
      case LessonProgressState.inProgress:
        return 'In progress';
      case LessonProgressState.completed:
        return 'Completed';
    }
  }

  IconData get icon {
    switch (this) {
      case LessonProgressState.notStarted:
        return Icons.radio_button_unchecked;
      case LessonProgressState.inProgress:
        return Icons.play_circle_outline;
      case LessonProgressState.completed:
        return Icons.check_circle_outline;
    }
  }
}

class LessonListItem {
  final int id;
  final String title;
  final String? subject;
  final String? difficulty;
  final String? thumbnail;
  final String? plan;
  final LessonProgressState progressState;

  const LessonListItem({
    required this.id,
    required this.title,
    required this.subject,
    required this.difficulty,
    required this.thumbnail,
    required this.plan,
    required this.progressState,
  });

  factory LessonListItem.fromJson(Map<String, dynamic> json) {
    return LessonListItem(
      id: (json['id'] as num).toInt(),
      title: (json['title'] ?? '').toString(),
      subject: json['subject']?.toString(),
      difficulty: json['difficulty']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      plan: json['plan']?.toString(),
      progressState: LessonProgressState.fromApi(
        json['progress_state']?.toString(),
      ),
    );
  }
}
