import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // import ThemeProvider

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  String _password = '';
  String _email = '';
  String _firstName = '';
  String _lastName = '';
  String? _errorMessage;
  bool _isLoading = false;

  String? get _apiUrl {
    final v = dotenv.env['API_URL']?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String get _baseUrl => "${_apiUrl ?? ''}/api/auth/";

  String _formatApiError(dynamic data, {String fallback = 'Signup failed'}) {
    if (data == null) return fallback;

    if (data is Map) {
      if (data['detail'] != null) return data['detail'].toString();
      if (data['error'] != null) return data['error'].toString();

      final parts = <String>[];
      for (final entry in data.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          parts.add('$key: ${value.join(' ')}');
        } else {
          parts.add('$key: $value');
        }
      }

      if (parts.isNotEmpty) return parts.join('\n');
    }

    if (data is List) {
      return data.map((e) => e.toString()).join('\n');
    }

    return data.toString();
  }

  void _signup() async {
    if (!_formKey.currentState!.validate()) return;

    final apiUrl = _apiUrl;
    if (apiUrl == null) {
      setState(() {
        _errorMessage =
            'Missing API_URL. Check frontend/assets/.env and restart the app.';
      });
      return;
    }

    final username = _username.trim();
    final password = _password;
    final email = _email.trim();
    final firstName = _firstName.trim();
    final lastName = _lastName.trim();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${_baseUrl}register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'email': email,
          'first_name': firstName,
          'last_name': lastName,
        }),
      );

      dynamic data;
      if (response.body.isNotEmpty) {
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          // Backend returned non-JSON (e.g., HTML error). Don't treat as offline.
          data = {'detail': response.body};
        }
      } else {
        data = null;
      }

      if (response.statusCode == 201) {
        // Auto-login after signup
        final tokenResp = await http.post(
          Uri.parse('${_baseUrl}token/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        );

        if (tokenResp.statusCode == 200) {
          dynamic tokenData;
          try {
            tokenData = jsonDecode(tokenResp.body);
          } catch (_) {
            tokenData = null;
          }
          if (tokenData is! Map || tokenData['access'] == null) {
            throw Exception('Token response was not valid JSON');
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', tokenData['access']);
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          // If token obtain fails, show error and fall back to login screen.
          dynamic tokenErr;
          try {
            tokenErr = tokenResp.body.isNotEmpty ? jsonDecode(tokenResp.body) : null;
          } catch (_) {
            tokenErr = {'detail': tokenResp.body};
          }
          setState(() {
            _errorMessage = _formatApiError(
              tokenErr,
              fallback: 'Signup succeeded but login failed (HTTP ${tokenResp.statusCode})',
            );
          });
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        setState(() {
          final formatted = _formatApiError(
            data,
            fallback: 'Signup failed (HTTP ${response.statusCode})',
          );
          if (formatted.toLowerCase().contains('username') &&
              formatted.toLowerCase().contains('already')) {
            _errorMessage =
                '$formatted\n\nIf you already created this username, try logging in.';
          } else {
            _errorMessage = formatted;
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Signup request failed. Check that the backend is running at $apiUrl.\n\nDetails: ${e.toString()}';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    final isDarkMode = themeProvider.isDarkMode;
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    return AnimatedTheme(
      data: theme,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: isSmallScreen
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Logo(isDarkMode: isDarkMode),
                            _FormContent(
                              formKey: _formKey,
                              onSignup: _signup,
                              isLoading: _isLoading,
                              onUserChange: (v) => _username = v,
                              onPassChange: (v) => _password = v,
                              onEmailChange: (v) => _email = v,
                              onFirstChange: (v) => _firstName = v,
                              onLastChange: (v) => _lastName = v,
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
                                    onSignup: _signup,
                                    isLoading: _isLoading,
                                    onUserChange: (v) => _username = v,
                                    onPassChange: (v) => _password = v,
                                    onEmailChange: (v) => _email = v,
                                    onFirstChange: (v) => _firstName = v,
                                    onLastChange: (v) => _lastName = v,
                                    errorMessage: _errorMessage,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              // Theme toggle button (animated)
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
                    onPressed: () {
                      themeProvider.toggleTheme();
                    },
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
          "Join Drawn Out!",
          textAlign: TextAlign.center,
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
  final void Function() onSignup;
  final void Function(String) onUserChange;
  final void Function(String) onPassChange;
  final void Function(String) onEmailChange;
  final void Function(String) onFirstChange;
  final void Function(String) onLastChange;
  final bool isLoading;
  final String? errorMessage;

  const _FormContent({
    required this.formKey,
    required this.onSignup,
    required this.isLoading,
    required this.onUserChange,
    required this.onPassChange,
    required this.onEmailChange,
    required this.onFirstChange,
    required this.onLastChange,
    this.errorMessage,
  });

  Widget _gap() => const SizedBox(height: 16);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
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
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: onEmailChange,
              validator: (val) => val!.isEmpty ? 'Enter an email' : null,
            ),
            _gap(),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'First Name',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: onFirstChange,
            ),
            _gap(),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Last Name',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: onLastChange,
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
                onPressed: isLoading ? null : onSignup,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Sign Up',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
            _gap(),
            TextButton(
              onPressed: () {
                Navigator.pushReplacementNamed(context, '/login');
              },
              child: const Text("Already have an account? Login"),
            ),
          ],
        ),
      ),
    );
  }
}
