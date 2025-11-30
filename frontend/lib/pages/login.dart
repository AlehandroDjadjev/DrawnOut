import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // To access ThemeProvider

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  String? _errorMessage;
  bool _isLoading = false;

  final String baseUrl = "${dotenv.env['API_URL']}/api/auth/";

  void _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${baseUrl}token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _username, 'password': _password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access']);
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        // Try to decode error message, but fallback safely
        String message = 'Login failed';
        try {
          final data = jsonDecode(response.body);
          message = data['detail'] ?? message;
        } catch (_) {}
        setState(() {
          _errorMessage = message;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Could not connect to server';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final theme = Theme.of(context);
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    return AnimatedTheme(
      data: theme,
      duration: const Duration(milliseconds: 400),
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: isSmallScreen
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Logo(isDarkMode: isDarkMode),
                          _FormContent(
                            formKey: _formKey,
                            isLoading: _isLoading,
                            onLogin: _login,
                            onUserChange: (v) => _username = v,
                            onPassChange: (v) => _password = v,
                            errorMessage: _errorMessage,
                          ),
                        ],
                      )
                    : Container(
                        padding: const EdgeInsets.all(32.0),
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: Row(
                          children: [
                            Expanded(child: _Logo(isDarkMode: isDarkMode)),
                            Expanded(
                              child: Center(
                                child: _FormContent(
                                  formKey: _formKey,
                                  isLoading: _isLoading,
                                  onLogin: _login,
                                  onUserChange: (v) => _username = v,
                                  onPassChange: (v) => _password = v,
                                  errorMessage: _errorMessage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              // Theme Toggle Button
              Positioned(
                top: 16,
                right: 16,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return RotationTransition(
                      turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: IconButton(
                    key: ValueKey(isDarkMode ? "dark" : "light"),
                    icon: Icon(
                      isDarkMode ? Icons.dark_mode : Icons.light_mode,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    tooltip: isDarkMode
                        ? "Switch to Light Mode"
                        : "Switch to Dark Mode",
                    onPressed: themeProvider.toggleTheme,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  final bool isDarkMode;
  const _Logo({required this.isDarkMode});

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.school,
            size: isSmallScreen ? 100 : 200,
            color: isDarkMode ? Colors.tealAccent.shade200 : Colors.blue),
        const SizedBox(height: 16),
        Text(
          "Welcome to Drawn Out!",
          style: TextStyle(
            fontSize: isSmallScreen ? 22 : 28,
            fontWeight: FontWeight.bold,
            color:
                isDarkMode ? Colors.tealAccent.shade100 : Colors.blueGrey[800],
          ),
        ),
      ],
    );
  }
}

class _FormContent extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final String? errorMessage;
  final void Function() onLogin;
  final void Function(String) onUserChange;
  final void Function(String) onPassChange;

  const _FormContent({
    required this.formKey,
    required this.onLogin,
    required this.onUserChange,
    required this.onPassChange,
    required this.isLoading,
    this.errorMessage,
  });

  Widget _gap() => const SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                onChanged: onUserChange,
                validator: (val) => val!.isEmpty ? 'Enter a username' : null,
              ),
              _gap(),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline_rounded),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
                onChanged: onPassChange,
                validator: (val) => val!.isEmpty ? 'Enter a password' : null,
              ),
              if (errorMessage != null) ...[
                _gap(),
                Text(
                  errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              _gap(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : onLogin,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Login',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ),
              _gap(),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/signup');
                },
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
