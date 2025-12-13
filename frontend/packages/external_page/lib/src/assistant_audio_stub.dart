// Non-web fallback using just_audio (already in pubspec) to play direct URLs.
import 'package:just_audio/just_audio.dart';

String _apiBaseUrl = '';
final _player = AudioPlayer();

void setAssistantAudioBaseUrl(String baseUrl) { _apiBaseUrl = baseUrl; }
void disposeAssistantAudio() { try { _player.dispose(); } catch (_) {} }
void setAssistantOnQueueEmpty(void Function() cb) {}

void enqueueAssistantAudioFromSession(Map<String, dynamic> session) async {
  final utt = (session['utterances'] as List?) ?? const [];
  if (utt.isEmpty) return;
  for (var i = utt.length - 1; i >= 0; i--) {
    final u = utt[i] as Map?; if (u == null) continue;
    if (u['role'] == 'tutor' && (u['audio_file'] ?? '').toString().isNotEmpty) {
      final url = (u['audio_file']).toString();
      try { await _player.setUrl(url); await _player.play(); } catch (_) {}
      break;
    }
  }
}


