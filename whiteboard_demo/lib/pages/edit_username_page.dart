import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../services/app_config_service.dart';

class EditUsernamePage extends StatefulWidget {
  final String currentUsername;

  const EditUsernamePage({super.key, required this.currentUsername});

  @override
  State<EditUsernamePage> createState() => _EditUsernamePageState();
}

class _EditUsernamePageState extends State<EditUsernamePage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _usernameController;
  bool _isLoading = false;
  String? _message;

  String get baseUrl {
    try {
      final config = Provider.of<AppConfigService>(context, listen: false);
      return '${config.backendUrl}/api/';
    } catch (_) {
      final envUrl = dotenv.env['API_URL'];
      return '${envUrl ?? 'http://127.0.0.1:8000'}/api/';
    }
  }

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.currentUsername);
  }

  Future<void> _updateUsername() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('Not logged in');

      final response = await http.put(
        Uri.parse('${baseUrl}auth/update_username/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'username': _usernameController.text}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _message = "Username updated successfully!";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Username updated successfully")),
        );
        Navigator.pop(context, true); // return success to ProfilePage
      } else {
        setState(() {
          _message = "Failed to update username";
        });
      }
    } catch (e) {
      setState(() {
        _message = "Could not connect to server";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Username")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: "New Username",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (val) =>
                    val!.isEmpty ? "Enter a valid username" : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateUsername,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Save Changes",
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!,
                    style: TextStyle(
                        color: _message!.contains("success")
                            ? Colors.green
                            : Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
