import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/timeline.dart';

/// Service for interacting with the timeline API
class TimelineApiService {
  final String baseUrl;

  TimelineApiService({this.baseUrl = 'http://localhost:8000'});

  String _api(String path) =>
      '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/api$path';

  /// Generate a new timeline for a session
  /// [useExistingImages] when true, skips image research and uses existing DB images
  Future<SyncedTimeline> generateTimeline(
    int sessionId, {
    double durationTarget = 60.0,
    bool regenerate = false,
    bool? useExistingImages,
  }) async {
    final url = Uri.parse(_api('/timeline/generate/$sessionId/'));
    final body = <String, dynamic>{
      'duration_target': durationTarget,
      'regenerate': regenerate,
    };
    if (useExistingImages != null) {
      body['use_existing_images'] = useExistingImages;
    }
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode ~/ 100 != 2) {
      throw Exception(
          'Failed to generate timeline: ${response.statusCode} ${response.body}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return SyncedTimeline.fromJson(data);
  }

  /// Get an existing timeline by ID
  Future<SyncedTimeline> getTimeline(int timelineId) async {
    final url = Uri.parse(_api('/timeline/$timelineId/'));
    final response = await http.get(url);

    if (response.statusCode ~/ 100 != 2) {
      throw Exception('Failed to get timeline: ${response.statusCode}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return SyncedTimeline.fromJson(data);
  }

  /// Get the latest timeline for a session
  Future<SyncedTimeline> getSessionTimeline(int sessionId) async {
    final url = Uri.parse(_api('/timeline/session/$sessionId/'));
    final response = await http.get(url);

    if (response.statusCode ~/ 100 != 2) {
      throw Exception('Failed to get session timeline: ${response.statusCode}');
    }

    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return SyncedTimeline.fromJson(data);
  }
}
