import 'dart:convert';
import 'package:http/http.dart' as http;

class WhiteboardPlanner {
  WhiteboardPlanner(this.baseUrl);

  final String baseUrl; // e.g., http://127.0.0.1:8000

  String _api(String path) => baseUrl.replaceFirst(RegExp(r'/+$'), '') + '/api' + path;

  Future<Map<String, dynamic>?> planForSession(Map<String, dynamic> sessionData) async {
    try {
      final token = await _getLiveToken();
      if (token == null || token.isEmpty) return null;
      final prompt = _buildPrompt(sessionData);
      final text = await _geminiGenerate(token, prompt);
      if (text == null) return null;
      final jsonStr = _extractJson(text);
      if (jsonStr == null) return null;
      final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
      return obj;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _getLiveToken() async {
    final resp = await http.get(Uri.parse(_api('/lessons/token/')));
    if (resp.statusCode ~/ 100 != 2) return null;
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    return (body is Map && body['token'] is String) ? body['token'] as String : null;
  }

  String _buildPrompt(Map<String, dynamic> s) {
    final topic = s['topic'] ?? '';
    final uts = (s['utterances'] as List? ?? const [])
        .cast<Map>()
        .where((u) => (u['role'] == 'tutor') && (u['text'] ?? '').toString().trim().isNotEmpty)
        .toList();
    final lastTexts = uts.reversed.take(8).toList().reversed.map((u) => '- ' + (u['text'] as String)).join('\n');

    // Condensed system prompt (from user spec)
    const sys = r'''
You produce whiteboard plans for a talking tutor. Do NOT caption speech. Only render concise visuals: headings, key terms, formulas, numbered steps, short bullets, mini labels/arrows (text-only), simple tables or comparisons. Keep it skimmable.
Output MUST be a single JSON object with key "whiteboard_actions": an array of items in order. Supported types: heading, bullet, subbullet, formula, label, table, diagram, note. Each item has: { "type": ..., "text": "...", ["level": 1|2|3], ["style": {"fontSize": number, "bold": boolean}] }.
Rules:
- Human-like flow: left→right, top→bottom. You only decide content order.
- Max ~5 bullets per cluster, then start a new heading/section.
- Keep bullets short (~10 words). Prefer symbols: →, ≈, ∝, ≠.
- Formulas on their own line. Key terms ALL CAPS if helpful.
- No filler, no subtitles, no long sentences.
''';

    final user = 'Topic: $topic\nRecent tutor points:\n$lastTexts\n\nReturn ONLY the JSON object.';
    return sys + '\n' + user;
  }

  Future<String?> _geminiGenerate(String apiKey, String prompt) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey');
    final body = {
      'contents': [
        {
          'parts': [ {'text': prompt} ]
        }
      ]
    };
    final resp = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (resp.statusCode ~/ 100 != 2) return null;
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    try {
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final parts = candidates[0]['content']['parts'];
        if (parts is List && parts.isNotEmpty) {
          return parts[0]['text'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _extractJson(String text) {
    // If the model wrapped JSON in code fences, extract content between first { and last }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return text.substring(start, end + 1);
    }
    return null;
  }
}


