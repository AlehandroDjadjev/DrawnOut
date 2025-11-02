import 'dart:convert';
import 'package:http/http.dart' as http;

class WhiteboardPlanner {
  WhiteboardPlanner(this.baseUrl);

  final String baseUrl; // e.g., http://127.0.0.1:8000

  String _api(String path) => baseUrl.replaceFirst(RegExp(r'/+$'), '') + '/api' + path;

  Future<Map<String, dynamic>?> planForSession(
    Map<String, dynamic> sessionData, {
    int maxItems = 3,
    int maxSentencesPerItem = 1,
    int maxWordsPerSentence = 10,
  }) async {
    try {
      print('🔍 Planner: Fetching token...');
      final token = await _getLiveToken();
      if (token == null || token.isEmpty) {
        print('❌ Planner: No token returned from /api/lessons/token/');
        print('   Trying fallback: simple extraction from session data');
        return _fallbackPlan(sessionData, maxItems, maxSentencesPerItem, maxWordsPerSentence);
      }
      print('✅ Planner: Got token');
      final prompt = _buildPrompt(sessionData, maxItems, maxSentencesPerItem, maxWordsPerSentence);
      print('🔍 Planner: Calling Gemini...');
      final text = await _geminiGenerate(token, prompt);
      if (text == null) {
        print('❌ Planner: Gemini returned null, using fallback');
        return _fallbackPlan(sessionData, maxItems, maxSentencesPerItem, maxWordsPerSentence);
      }
      print('✅ Planner: Gemini response length: ${text.length}');
      final jsonStr = _extractJson(text);
      if (jsonStr == null) {
        print('❌ Planner: Could not extract JSON from response: $text');
        print('   Using fallback plan');
        return _fallbackPlan(sessionData, maxItems, maxSentencesPerItem, maxWordsPerSentence);
      }
      print('✅ Planner: Extracted JSON: $jsonStr');
      final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
      final actions = (obj['whiteboard_actions'] as List?) ?? const [];
      print('✅ Planner: Got ${actions.length} raw actions');
      final sanitized = _sanitizeActions(actions, maxItems, maxSentencesPerItem, maxWordsPerSentence);
      print('✅ Planner: Sanitized to ${sanitized.length} actions');
      // Extract diagram hint if present
      final hint = (obj['diagram_hint'] ?? obj['diagram'] ?? obj['image_hint'] ?? '') as Object?;
      return {
        'whiteboard_actions': sanitized,
        if (hint is String && hint.trim().isNotEmpty) 'diagram_hint': hint.trim(),
      };
    } catch (e, st) {
      print('❌ Planner ERROR: $e');
      print('Stack: $st');
      print('   Using fallback plan');
      return _fallbackPlan(sessionData, maxItems, maxSentencesPerItem, maxWordsPerSentence);
    }
  }

  /// Fallback: extract key points directly from session data without Gemini
  Map<String, dynamic> _fallbackPlan(
    Map<String, dynamic> sessionData,
    int maxItems,
    int maxSentences,
    int maxWords,
  ) {
    print('📋 Generating fallback plan from session data');
    final topic = (sessionData['topic'] ?? 'Lesson').toString();
    final utterances = (sessionData['utterances'] as List?) ?? [];
    
    final actions = <Map<String, dynamic>>[];
    
    // Add topic as heading
    actions.add({
      'type': 'heading',
      'text': _trimSentencesAndWords(topic, 1, maxWords),
    });
    
    // Extract tutor utterances and convert to bullet points
    final tutorTexts = utterances
        .where((u) => u is Map && u['role'] == 'tutor' && (u['text'] ?? '').toString().trim().isNotEmpty)
        .map((u) => (u as Map)['text'].toString())
        .take(maxItems - 1) // Reserve one for the heading
        .toList();
    
    for (final text in tutorTexts) {
      if (actions.length >= maxItems) break;
      // Extract first sentence or key phrase
      final trimmed = _trimSentencesAndWords(text, maxSentences, maxWords);
      if (trimmed.isNotEmpty) {
        actions.add({
          'type': 'heading',
          'text': trimmed,
          'level': 1,
        });
      }
    }
    
    if (actions.isEmpty) {
      actions.add({'type': 'heading', 'text': 'KEY POINTS'});
    }
    
    print('✅ Fallback plan generated with ${actions.length} actions');
    return {'whiteboard_actions': actions};
  }

  Future<String?> _getLiveToken() async {
    final resp = await http.get(Uri.parse(_api('/lessons/token/')));
    if (resp.statusCode ~/ 100 != 2) return null;
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    return (body is Map && body['token'] is String) ? body['token'] as String : null;
  }

  String _buildPrompt(Map<String, dynamic> s, int maxItems, int maxSentences, int maxWords) {
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

STRICT LIMITS FOR THIS APP:
- Return AT MOST ${MAX_ITEMS} items total (≈ sentences total).
- ALWAYS use type "heading" for every item (no body/bullets/subbullets).
- Use AT MOST ${MAX_SENTENCES} sentence(s) per item and ≤ ${MAX_WORDS} words per sentence.
- Prefer 1–3 concise headings (or formulas as text headings) that capture ONLY the most important points.
- Content must fit naturally within ~40 seconds of speech for the segment.

Additionally, decide whether a single simple diagram would help. If YES, include a field "diagram_hint" at top-level of the JSON with an EXPLICIT, CONCRETE description of exactly what to draw (not a topic). The hint must:
- Be extremely specific about primitives and layout (e.g., "one right triangle, label sides a,b,c as text is NOT allowed here; instead describe shapes/relations only, e.g., 'one right triangle with a small square on the hypotenuse'"),
- Avoid text/labels in the image itself,
- Prefer minimal shapes and as few strokes as possible.
''';

    final promptWithLimits = sys
        .replaceAll('MAX_ITEMS', maxItems.toString())
        .replaceAll('MAX_WORDS', maxWords.toString())
        .replaceAll('MAX_SENTENCES', maxSentences.toString());

    final user = 'Topic: $topic\nRecent tutor points:\n$lastTexts\n\nReturn ONLY the JSON object.';
    return promptWithLimits + '\n' + user;
  }

  Future<String?> _geminiGenerate(String apiKey, String prompt) async {
    // Use the stable v1beta endpoint with the latest model names as of Oct 2025
    // Priority order: newest experimental -> stable production -> fallback
    final modelNames = [
      'gemini-2.0-flash-exp',           // Latest experimental (Oct 2025)
      'gemini-1.5-flash-latest',        // Latest stable flash
      'gemini-1.5-flash',               // Stable fallback
      'gemini-1.5-pro-latest',          // Pro if flash unavailable
      'gemini-pro',                     // Legacy fallback
    ];
    
    const baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
    
    final body = {
      'contents': [
        {
          'parts': [ {'text': prompt} ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 800,
      }
    };
    
    for (final modelName in modelNames) {
      try {
        final endpoint = '$baseUrl/models/$modelName:generateContent';
        print('🔍 Trying model: $modelName');
        final uri = Uri.parse('$endpoint?key=$apiKey');
        final resp = await http.post(
          uri, 
          headers: {'Content-Type': 'application/json'}, 
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 30));
        
        print('   Response status: ${resp.statusCode}');
        
        if (resp.statusCode == 404) {
          print('   ⚠️ Model not found, trying next...');
          continue;
        }
        
        if (resp.statusCode ~/ 100 != 2) {
          print('   ❌ Failed with status ${resp.statusCode}: ${resp.body}');
          continue;
        }
        
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        try {
          final candidates = data['candidates'];
          if (candidates is List && candidates.isNotEmpty) {
            final parts = candidates[0]['content']['parts'];
            if (parts is List && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.isNotEmpty) {
                print('   ✅ Success with model: $modelName');
                return text;
              }
            }
          }
          print('   ⚠️ Response structure unexpected, trying next model');
        } catch (e) {
          print('   ❌ Failed to parse response: $e');
        }
      } catch (e) {
        print('   ❌ Request error for $modelName: $e');
      }
    }
    
    print('❌ All Gemini models failed');
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

  List<Map<String, dynamic>> _sanitizeActions(
    List actions,
    int maxItems,
    int maxSentences,
    int maxWords,
  ) {
    final out = <Map<String, dynamic>>[];
    Map<String, dynamic>? heading;
    Map<String, dynamic>? formula;
    final bullets = <Map<String, dynamic>>[];

    for (final a in actions) {
      if (a is! Map) continue;
      final type = (a['type'] ?? '').toString();
      final text = (a['text'] ?? '').toString();
      if (text.trim().isEmpty) continue;
      final trimmed = _trimSentencesAndWords(text, maxSentences, maxWords);
      final m = {
        'type': 'heading',
        'text': trimmed,
        if (a['level'] != null) 'level': a['level'],
        if (a['style'] != null) 'style': a['style'],
      };
      if (type == 'heading' && heading == null) heading = m;
      else if (type == 'formula' && formula == null) formula = m;
      else { bullets.add({'type': 'heading', 'text': trimmed, 'level': 1}); }
    }

    if (heading != null) out.add(heading!);
    if (formula != null && out.length < maxItems) out.add(formula!);
    for (final b in bullets) {
      if (out.length >= maxItems) break;
      out.add(b);
    }
    // Ensure not empty: if nothing, return one note
    if (out.isEmpty) {
      out.add({'type': 'heading', 'text': 'KEY IDEA'});
    }
    return out;
  }

  String _trimSentencesAndWords(String s, int maxSentences, int maxWords) {
    final text = s.trim();
    if (text.isEmpty) return text;
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    final takeS = sentences.take(maxSentences);
    final trimmedSentences = takeS.map((sent) {
      final words = sent.trim().split(RegExp(r'\s+'));
      final kept = words.take(maxWords).join(' ');
      return kept;
    }).toList();
    return trimmedSentences.join(' ');
  }
}


