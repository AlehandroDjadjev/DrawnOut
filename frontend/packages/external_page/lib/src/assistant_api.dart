import 'dart:convert';
import 'package:http/http.dart' as http;

class AssistantApiClient {
  AssistantApiClient(String baseUrl)
      : baseUrl = _normalizeBase(baseUrl);

  String baseUrl; // normalized like http://127.0.0.1:8000

  static String _normalizeBase(String url) {
    var u = (url.isEmpty ? 'http://127.0.0.1:8000/' : url.trim());
    if (!u.startsWith('http')) u = 'http://127.0.0.1:8000/';
    while (u.endsWith('/')) { u = u.substring(0, u.length - 1); }
    // If user passed .../api or .../api/lessons, strip it to the root
    u = u.replaceFirst(RegExp(r'/api/lessons$'), '').replaceFirst(RegExp(r'/api$'), '');
    return u;
  }

  Uri _u(String path) => Uri.parse('$baseUrl/api$path');

  Future<Map<String, dynamic>> startLesson({String topic = 'Pythagorean Theorem'}) async {
    final resp = await http.post(_u('/lessons/start/'), body: {'topic': topic});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw StateError('startLesson failed: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> nextSegment(int sessionId) async {
    final resp = await http.post(_u('/lessons/$sessionId/next/'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw StateError('nextSegment failed: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> raiseHand(int sessionId, {String? question, bool startLive = false}) async {
    final body = <String, String>{};
    if (question != null && question.isNotEmpty) body['question'] = question;
    if (startLive) body['start_live'] = 'true';
    final resp = await http.post(_u('/lessons/$sessionId/raise-hand/'), body: body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw StateError('raiseHand failed: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> liveMessage(int sessionId, String message) async {
    final resp = await http.post(_u('/lessons/$sessionId/live/'), body: {'message': message});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw StateError('liveMessage failed: ${resp.statusCode}');
  }

  Future<Map<String, dynamic>> sessionDetail(int sessionId) async {
    final resp = await http.get(_u('/lessons/$sessionId/'));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    }
    throw StateError('sessionDetail failed: ${resp.statusCode}');
  }
}


