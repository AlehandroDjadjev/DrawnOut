import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Android emulator = 10.0.2.2
  static const String baseUrl = "http://127.0.0.1:8000";

  static Future<Map<String, dynamic>> fetchTest() async {
    final response = await http.post(
      Uri.parse("$baseUrl/api/tests/generate-test/"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "prompt": "Create a history test about the French Revolution"
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Failed to load test");
    }
  }
}
