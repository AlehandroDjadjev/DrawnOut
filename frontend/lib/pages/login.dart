import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_provider/theme_provider.dart';
import '../services/app_config_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();

  String _username = '';
  String _password = '';

  String? _errorMessage;
  bool _isLoading = false;

  String? get _apiUrl {
    // Try AppConfigService first, then dotenv
    try {
      final config = Provider.of<AppConfigService>(context, listen: false);
      final url = config.backendUrl;
      if (url.isNotEmpty) return url;
    } catch (_) {}
    
    final v = dotenv.env['API_URL']?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  String get _baseUrl => "${_apiUrl ?? ''}/api/auth/";

  String _formatApiError(dynamic data, {String fallback = 'Login failed'}) {
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

  Future<void> _login() async {
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${_baseUrl}token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access']);
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        String message = 'Login failed';
        try {
          final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
          message = _formatApiError(data, fallback: message);
        } catch (_) {
          // Keep fallback
        }

        if (message.toLowerCase().contains('no active account found') ||
            message.toLowerCase().contains('given credentials')) {
          message = 'Incorrect username or password.';
        }
        setState(() {
          _errorMessage = message;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not connect to server');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = context.watch<ThemeProvider>().isDarkMode;
    final themeProvider = context.read<ThemeProvider>();
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: isSmallScreen
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _Logo(),
                            _FormContent(
                              formKey: _formKey,
                              isLoading: _isLoading,
                              onLogin: _login,
                              onUserChange: (v) => _username = v,
                              onPassChange: (v) => _password = v,
                              errorMessage: _errorMessage,
                            ),
                          ],
                        ),
                      )
                    : Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        padding: const EdgeInsets.all(32),
                        child: Row(
                          children: [
                            const Expanded(child: _Logo()),
                            Expanded(
                              child: _FormContent(
                                formKey: _formKey,
                                isLoading: _isLoading,
                                errorMessage: _errorMessage,
                                onLogin: _login,
                                onUserChange: (v) => _username = v,
                                onPassChange: (v) => _password = v,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            /// Theme toggle
            Positioned(
              top: 16,
              right: 16,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (child, animation) {
                  return RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: IconButton(
                  key: ValueKey(isDarkMode),
                  icon: Icon(
                    isDarkMode ? Icons.dark_mode : Icons.light_mode,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: themeProvider.toggleTheme,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.school,
          size: isSmallScreen ? 100 : 180,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Welcome to DrawnOut!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
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

  final VoidCallback onLogin;
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

    return Form(
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
            validator: (v) => v!.isEmpty ? 'Enter a username' : null,
          ),
          _gap(),
          TextFormField(
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: onPassChange,
            validator: (v) => v!.isEmpty ? 'Enter a password' : null,
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
                padding: const EdgeInsets.all(12),
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ),
          _gap(),
          TextButton(
            onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
            child: const Text("Don't have an account? Sign Up"),
          ),
        ],
      ),
    );
  }
}
