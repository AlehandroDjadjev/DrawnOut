import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme_provider/theme_provider.dart';
import '../ui/apple_ui.dart';
import '../services/app_config_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
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

  Future<void> _signup() async {
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
          if (!mounted) return;
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
        if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Signup request failed. Check that the backend is running at $_apiUrl.\n\nDetails: ${e.toString()}';
      });
    }

    if (mounted) {
      setState(() => _isLoading = false);
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
                      maxWidth: isSmallScreen ? 560 : 820,
                    ),
                    child: isSmallScreen
                        ? _AppleSignupCard(
                            formKey: _formKey,
                            isLoading: _isLoading,
                            errorMessage: _errorMessage,
                            onSignup: _signup,
                            onUserChange: (v) => _username = v,
                            onPassChange: (v) => _password = v,
                            onEmailChange: (v) => _email = v,
                            onFirstChange: (v) => _firstName = v,
                            onLastChange: (v) => _lastName = v,
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
                                        title: 'Create your account',
                                        subtitle:
                                            'Join DrawnOut to access lessons, the market, and the whiteboard.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _AppleSignupCard(
                                  formKey: _formKey,
                                  isLoading: _isLoading,
                                  errorMessage: _errorMessage,
                                  onSignup: _signup,
                                  onUserChange: (v) => _username = v,
                                  onPassChange: (v) => _password = v,
                                  onEmailChange: (v) => _email = v,
                                  onFirstChange: (v) => _firstName = v,
                                  onLastChange: (v) => _lastName = v,
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

class _AppleSignupCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final bool isLoading;
  final String? errorMessage;

  final VoidCallback onSignup;
  final void Function(String) onUserChange;
  final void Function(String) onPassChange;
  final void Function(String) onEmailChange;
  final void Function(String) onFirstChange;
  final void Function(String) onLastChange;

  const _AppleSignupCard({
    required this.formKey,
    required this.isLoading,
    required this.errorMessage,
    required this.onSignup,
    required this.onUserChange,
    required this.onPassChange,
    required this.onEmailChange,
    required this.onFirstChange,
    required this.onLastChange,
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
              title: 'Sign up',
              subtitle: 'Create an account in under a minute.',
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
                hintText: 'Email',
                icon: Icons.email_outlined,
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: onEmailChange,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter an email'
                  : null,
            ),
            _gap(),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    decoration: appleFieldDecoration(
                      context,
                      hintText: 'First name',
                      icon: Icons.badge_outlined,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: onFirstChange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    decoration: appleFieldDecoration(
                      context,
                      hintText: 'Last name',
                      icon: Icons.badge_outlined,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: onLastChange,
                  ),
                ),
              ],
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
                if (!isLoading) onSignup();
              },
            ),
            if (errorMessage != null) ...[
              _gap(),
              AppleErrorBanner(message: errorMessage!),
            ],
            _gap(),
            ApplePrimaryButton(
              label: 'Create account',
              onPressed: onSignup,
              loading: isLoading,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
                child: Text(
                  'Already have an account? Sign in',
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
