import 'package:flutter/material.dart';

// ✅ Import from correct folder
import '../whiteboard_functionality/assistant_api.dart';
import '../whiteboard_functionality/assistant_audio.dart';
import '../whiteboard_functionality/sdk_live_bridge.dart';

class LessonPage extends StatefulWidget {
  const LessonPage({super.key});

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final _api =
      AssistantApiClient("http://127.0.0.1:8000"); // change to your server
  final _audio = AssistantAudio();

  int? _sessionId;
  String _tutorMessage = "Connecting to tutor...";
  bool _isSpeaking = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _startLesson();
  }

  Future<void> _startLesson() async {
    try {
      final data = await _api.startLesson(topic: "Pythagorean Theorem");
      setState(() {
        _sessionId = data['id'] as int;
        _tutorMessage = (data['message'] ?? "Lesson started!") as String;
        _loading = false;
      });
      _playAudioIfAvailable(data);
    } catch (e) {
      setState(() {
        _tutorMessage = "❌ Failed to start lesson: $e";
        _loading = false;
      });
    }
  }

  Future<void> _nextSegment() async {
    if (_sessionId == null) return;
    try {
      final data = await _api.nextSegment(_sessionId!);
      setState(() {
        _tutorMessage = (data['message'] ?? "…") as String;
      });
      _playAudioIfAvailable(data);
    } catch (e) {
      setState(() => _tutorMessage = "⚠️ Error: $e");
    }
  }

  Future<void> _onRaiseHand() async {
    if (_sessionId == null) return;
    try {
      final data =
          await _api.raiseHand(_sessionId!, question: "Can you explain again?");
      setState(() {
        _tutorMessage = (data['message'] ?? "Tutor is answering...") as String;
      });
      _playAudioIfAvailable(data);
    } catch (e) {
      setState(() => _tutorMessage = "⚠️ Error: $e");
    }
  }

  Future<void> _playAudioIfAvailable(Map<String, dynamic> data) async {
    final utt = (data['utterances'] as List?) ?? [];
    if (utt.isEmpty) return;

    final tutorUtterances = utt.where((u) => u['role'] == 'tutor');
    if (tutorUtterances.isEmpty) return;

    final audioUrl = tutorUtterances.last['audio_file']?.toString();
    if (audioUrl != null && audioUrl.isNotEmpty) {
      setState(() => _isSpeaking = true);
      await _audio.playFromUrl(audioUrl); // your assistant_audio handles this
      setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Tutor Lesson"),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tutor Message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue.shade50,
                  child: Text(
                    _tutorMessage,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),

                // Drawing Canvas (expandable)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white,
                    ),
                    child: const Center(
                      child: Text("📐 AI Tutor’s drawings will appear here"),
                    ),
                  ),
                ),

                // Controls
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _onRaiseHand,
                          icon: const Icon(Icons.pan_tool),
                          label: const Text("Raise Hand"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _nextSegment,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text("Next"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
