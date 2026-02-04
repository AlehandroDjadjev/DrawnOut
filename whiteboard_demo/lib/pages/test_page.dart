import 'package:flutter/material.dart';

class TestPage extends StatefulWidget {
  final Map<String, dynamic> testData;

  const TestPage({super.key, required this.testData});

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  final Map<int, String> part1Answers = {};
  final Map<int, String> part2Answers = {};

  bool get isFinished {
    final part1 = widget.testData["part1"] as List;
    final part2 = widget.testData["part2"] as List;

    return part1Answers.length == part1.length &&
        part2Answers.length == part2.length;
  }

  void submitTest() {
    final part1 = widget.testData["part1"] as List;

    int correct = 0;

    for (int i = 0; i < part1.length; i++) {
      final correctAnswer = part1[i]["correct_answer"];
      if (part1Answers[i] == correctAnswer) {
        correct++;
      }
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Result"),
        content: Text(
            "You got $correct / ${part1.length} multiple choice questions correct."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final part1 = widget.testData["part1"] as List;
    final part2 = widget.testData["part2"] as List;

    return Scaffold(
      appBar: AppBar(title: const Text("Test")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Part 1 - Multiple Choice",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

          for (int i = 0; i < part1.length; i++)
            _buildMCQ(i, part1[i]),

          const SizedBox(height: 24),

          const Text("Part 2 - Open Questions",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),

          for (int i = 0; i < part2.length; i++)
            _buildOpen(i, part2[i]),

          const SizedBox(height: 30),

          ElevatedButton(
            onPressed: isFinished ? submitTest : null,
            child: const Text("Submit"),
          ),

          if (!isFinished)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                "Finish all questions before submitting",
                style: TextStyle(color: Colors.red),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildMCQ(int index, Map<String, dynamic> q) {
    final choices = q["choices"] as List;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text("${index + 1}. ${q["question"]}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...choices.map(
            (c) => RadioListTile<String>(
              title: Text(c),
              value: c,
              groupValue: part1Answers[index],
              onChanged: (v) {
                setState(() {
                  part1Answers[index] = v!;
                });
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOpen(int index, Map<String, dynamic> q) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text("${index + 1}. ${q["question"]}",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              maxLines: 4,
              onChanged: (v) {
                part2Answers[index] = v;
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "Your answer",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
