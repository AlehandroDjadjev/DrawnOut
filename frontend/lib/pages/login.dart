import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_provider/theme_provider.dart';
import '../ui/apple_ui.dart';

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
        if (!mounted) return;
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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: AppleBackground(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return RotationTransition(
                        turns:
                            Tween(begin: 0.75, end: 1.0).animate(animation),
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: IconButton(
                      key: ValueKey(isDarkMode),
                      icon: Icon(
                        isDarkMode ? Icons.dark_mode : Icons.light_mode,
                        size: 26,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: themeProvider.toggleTheme,
                    ),
                  ),
                ),
              ),

              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isSmallScreen ? 520 : 720,
                    ),
                    child: isSmallScreen
                        ? _AppleLoginCard(
                            formKey: _formKey,
                            isLoading: _isLoading,
                            errorMessage: _errorMessage,
                            onLogin: _login,
                            onUserChange: (v) => _username = v,
                            onPassChange: (v) => _password = v,
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(right: 24, top: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.school,
                                        size: 56,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(height: 14),
                                      const AppleHeader(
                                        title: 'Welcome back',
                                        subtitle:
                                            'Sign in to continue your lessons and whiteboard practice.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _AppleLoginCard(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _AppleLoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final String? errorMessage;

  final VoidCallback onLogin;
  final void Function(String) onUserChange;
  final void Function(String) onPassChange;

  const _AppleLoginCard({
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

    return AppleCard(
      padding: const EdgeInsets.all(18),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppleHeader(
              title: 'Sign in',
              subtitle: 'Use your account to continue.',
            ),
            _gap(),
            TextFormField(
              decoration: appleFieldDecoration(
                context,
                hintText: 'Username',
                icon: Icons.person_outline,
              ),
              textInputAction: TextInputAction.next,
              onChanged: onUserChange,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter a username'
                  : null,
            ),
            _gap(),
            TextFormField(
              decoration: appleFieldDecoration(
                context,
                hintText: 'Password',
                icon: Icons.lock_outline,
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onChanged: onPassChange,
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Enter a password'
                  : null,
              onFieldSubmitted: (_) {
                if (!isLoading) onLogin();
              },
            ),
            if (errorMessage != null) ...[
              _gap(),
              AppleErrorBanner(message: errorMessage!),
            ],
            _gap(),
            ApplePrimaryButton(
              label: 'Continue',
              onPressed: onLogin,
              loading: isLoading,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/signup'),
                child: Text(
                  "Don't have an account? Create one",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
