import 'package:flutter/material.dart';
import '../services/test_gen_api.dart';
import 'test_page.dart';

class GeneratorPage extends StatelessWidget {
  const GeneratorPage({super.key});

  void loadTest(BuildContext context) async {
    final data = await ApiService.fetchTest();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TestPage(testData: data),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Generate Test")),
      body: Center(
        child: ElevatedButton(
          onPressed: () => loadTest(context),
          child: const Text("Load Test"),
        ),
      ),
    );
  }
}
