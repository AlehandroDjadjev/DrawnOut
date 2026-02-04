// Web-only assistant audio playback, mirroring backend/templates/index.html logic.
// - Queues new tutor utterances
// - Plays HTMLAudio; falls back to SpeechSynthesis on failure or missing audio
// - Resolves relative media paths against configured API base URL

import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String _apiBaseUrl = '';
final List<Map<String, dynamic>> _queue = [];
final Set<int> _playedTutorIds = <int>{};
Object? _playing; // html.AudioElement or {type:'tts'}
bool _voicesLoaded = false;
void Function()? _onQueueEmpty;

void setAssistantAudioBaseUrl(String baseUrl) {
  _apiBaseUrl = baseUrl.trim();
  try {
    var cleaned = _apiBaseUrl.trim();
    if (cleaned.isEmpty) cleaned = 'http://127.0.0.1:8000/';
    while (cleaned.endsWith('/')) { cleaned = cleaned.substring(0, cleaned.length - 1); }
    cleaned = cleaned
      .replaceFirst(RegExp(r'/api/lessons$'), '')
      .replaceFirst(RegExp(r'/api$'), '');
    // Previously we also wrote the derived lessons base to a JS global.
    // This is optional; keep the Dart-side base URL for media resolution.
  } catch (_) {}
}

void disposeAssistantAudio() {
  try {
    if (_playing is html.AudioElement) {
      final a = _playing as html.AudioElement;
      a.pause();
      a.src = '';
    }
  } catch (_) {}
  _queue.clear();
  _playedTutorIds.clear();
  _playing = null;
}

void setAssistantOnQueueEmpty(void Function() cb) { _onQueueEmpty = cb; }

void enqueueAssistantAudioFromSession(Map<String, dynamic> session) {
  final utt = (session['utterances'] as List?) ?? const [];
  if (utt.isEmpty) return;
  final List<Map<String, dynamic>> newItems = [];
  for (final u in utt) {
    if (u is! Map) continue;
    final role = (u['role'] ?? '').toString();
    if (role != 'tutor') continue;
    final id = (u['id'] is int) ? (u['id'] as int) : int.tryParse('${u['id']}') ?? -1;
    if (id < 0 || _playedTutorIds.contains(id)) continue;
    final text = (u['text'] ?? '').toString();
    final url = _mediaUrl((u['audio_file'] ?? '').toString());
    newItems.add({ 'id': id, 'url': url, 'text': text });
  }
  if (newItems.isEmpty) return;
  _queue.addAll(newItems);
  if (_playing == null) {
    _playNext();
  }
}

String _originFromBase(String base) {
  try {
    final uri = Uri.parse(base);
    final port = (uri.hasPort && uri.port != 0) ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  } catch (_) {
    return '';
  }
}

String _mediaUrl(String path) {
  if (path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final origin = _originFromBase(_apiBaseUrl);
  if (origin.isEmpty) return path;
  if (path.startsWith('/')) return origin + path;
  final cleaned = path.replaceFirst(RegExp(r'^media/'), '');
  return '$origin/media/$cleaned';
}

Future<void> _ensureVoicesLoaded() async {
  if (_voicesLoaded) return;
  // Poll for voices for up to ~1s
  for (int i = 0; i < 20; i++) {
    final have = html.window.speechSynthesis?.getVoices();
    if (have != null && have.isNotEmpty) { _voicesLoaded = true; return; }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  _voicesLoaded = true;
}

html.SpeechSynthesisVoice? _chooseVoice() {
  final voices = html.window.speechSynthesis?.getVoices() ?? const <html.SpeechSynthesisVoice>[];
  const preferred = <String>[
    'Google US English Female',
    'Microsoft Aria Online (Natural) - English (United States)',
    'Microsoft Jenny Online (Natural) - English (United States)',
    'Samantha', 'Jenny', 'en-US-Wavenet-F', 'en-US-Neural2-F',
  ];
  for (final name in preferred) {
    final v = voices.where((v) => (v.name ?? '').contains(name)).toList();
    if (v.isNotEmpty) return v.first;
  }
  try { return voices.firstWhere((v) => RegExp('female', caseSensitive: false).hasMatch(v.name ?? '')); } catch (_) {}
  return voices.isNotEmpty ? voices.first : null;
}

Future<void> _speak(String text) async {
  if (text.trim().isEmpty) return;
  try {
    await _ensureVoicesLoaded();
    final utt = html.SpeechSynthesisUtterance(text)
      ..lang = 'en-US'
      ..rate = 1.0
      ..pitch = 1.0;
    final voice = _chooseVoice();
    if (voice != null) { utt.voice = voice; }
    final c = Completer<void>();
    utt.addEventListener('end', (_) => c.complete());
    utt.addEventListener('error', (_) => c.complete());
    html.window.speechSynthesis?.speak(utt);
    _playing = {'type': 'tts'};
    await c.future;
  } catch (_) {}
}

void _playNext() {
  if (_queue.isEmpty) { _playing = null; try { _onQueueEmpty?.call(); } catch (_) {} return; }
  final item = _queue.removeAt(0);
  final id = (item['id'] is int) ? (item['id'] as int) : int.tryParse('${item['id']}') ?? -1;
  if (id >= 0) _playedTutorIds.add(id);
  final url = (item['url'] ?? '').toString();
  final text = (item['text'] ?? '').toString();
  if (url.isNotEmpty) {
    try {
      final a = html.AudioElement(url)
        ..controls = false
        ..preload = 'auto'
        ..autoplay = false;
      _playing = a;
      a.onEnded.listen((_) { _playing = null; _playNext(); });
      a.onError.listen((_) { _playing = null; _speak(text).then((_) => _playNext()); });
      a.play().catchError((_) { _playing = null; _speak(text).then((_) => _playNext()); });
      return;
    } catch (_) {
      _speak(text).then((_) => _playNext());
      return;
    }
  }
  _speak(text).then((_) => _playNext());
}

// removed custom Completer shim; use dart:async Completer


