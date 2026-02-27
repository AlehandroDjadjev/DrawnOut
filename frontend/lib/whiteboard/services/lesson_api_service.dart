import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/auth_service.dart';

/// Response from starting a lesson
class LessonSessionResponse {
  final int id;
  final String topic;
  final bool isCompleted;
  final int currentStepIndex;

  LessonSessionResponse({
    required this.id,
    required this.topic,
    required this.isCompleted,
    required this.currentStepIndex,
  });

  factory LessonSessionResponse.fromJson(Map<String, dynamic> json) {
    return LessonSessionResponse(
      id: json['id'] as int,
      topic: (json['topic'] ?? '') as String,
      isCompleted: (json['is_completed'] ?? false) as bool,
      currentStepIndex: (json['current_step_index'] ?? 0) as int,
    );
  }
}

/// Service for lesson API calls - uses AuthService for automatic token refresh.
class LessonApiService {
  final String baseUrl;
  final AuthService _authService;

  LessonApiService({this.baseUrl = 'http://127.0.0.1:8000'})
      : _authService = AuthService(baseUrl: baseUrl);

  /// Set callback for when session expires (refresh failed).
  set onSessionExpired(void Function()? callback) {
    _authService.onSessionExpired = callback;
  }

  String _api(String path) =>
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/lessons$path';

  /// Start a new lesson session
  /// Returns the session response with session ID
  Future<LessonSessionResponse> startLesson({
    required String topic,
    String? authToken, // Kept for API compatibility but ignored - uses AuthService
  }) async {
    debugPrint('Starting lesson with topic: $topic');

    final response = await _authService.authenticatedPost(
      _api('/start/'),
      body: json.encode({'topic': topic}),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to start lesson: ${response.statusCode} - ${response.body}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return LessonSessionResponse.fromJson(data);
  }

  /// Get session details
  Future<LessonSessionResponse> getSession(int sessionId) async {
    final response = await _authService.authenticatedGet(
      _api('/$sessionId/'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get session: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return LessonSessionResponse.fromJson(data);
  }

  /// Request next segment in the lesson
  Future<LessonSessionResponse> nextSegment(int sessionId) async {
    final response = await _authService.authenticatedPost(
      _api('/$sessionId/next/'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to get next segment: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    return LessonSessionResponse.fromJson(data);
  }
}
