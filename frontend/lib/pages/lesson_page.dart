import 'package:flutter/material.dart';

// ✅ Import from the whiteboard_functionality folder
import '../whiteboard_functionality/assistant_api.dart';
import '../whiteboard_functionality/assistant_audio.dart'; // uses conditional export (web vs fallback)
import '../whiteboard_functionality/planner.dart';
import '../whiteboard_functionality/sdk_live_bridge.dart'; // handles start/stop live whiteboard (if needed)

class LessonPage extends StatefulWidget {
  const LessonPage({super.key});

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final AssistantApi _assistant = AssistantApi();
  final Planner _planner = Planner();

  // use interface instead of hardcoding AssistantAudioWeb
  final AssistantAudio _audio = AssistantAudio();

  String _tutorMessage =
      "Welcome! Let's begin learning about Pythagoras’ Theorem.";
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _startLesson();
  }

  Future<void> _startLesson() async {
    final firstStep = await _planner.getNextStep();
    _updateTutor(firstStep);
  }

  void _updateTutor(String message) async {
    setState(() {
      _tutorMessage = message;
      _isSpeaking = true;
    });

    await _audio.speak(message);

    setState(() {
      _isSpeaking = false;
    });
  }

  void _onRaiseHand() async {
    final response = await _assistant
        .askQuestion("✋ Student raised their hand to ask something.");
    _updateTutor(response);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Tutor Lesson"),
        centerTitle: true,
      ),
      body: Column(
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
                    label: const Text("Raise Hand / Ask Question"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
