// Conditional export: web uses HTMLAudio+SpeechSynthesis; other platforms use just_audio fallback.
export 'assistant_audio_stub.dart' if (dart.library.html) 'assistant_audio_web.dart';


