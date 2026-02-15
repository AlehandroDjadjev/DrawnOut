import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/developer_mode_provider.dart';
import '../services/auth_service.dart';

/// App entry gate:
/// - If no saved token -> go to /login
/// - If token exists -> validate against backend (/api/auth/profile/)
///   - 200 -> go to /home
///   - 401 -> try refresh token -> retry
///   - Still 401 -> clear tokens -> go to /login
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _loading = true;
  String? _error;

  String get _apiBaseUrl {
    final raw = (dotenv.env['API_URL'] ?? '').trim();
    if (raw.isEmpty) return 'http://127.0.0.1:8000';
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    try {
      final uri = Uri.parse('$_apiBaseUrl/api/auth/profile/');
      var resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      // If 401, try refreshing the token
      if (resp.statusCode == 401) {
        debugPrint('🔑 Access token expired, attempting refresh...');
        final authService = AuthService(baseUrl: _apiBaseUrl);
        final newToken = await authService.refreshAccessToken();

        if (newToken != null) {
          // Retry with new token
          resp = await http.get(
            uri,
            headers: {
              'Authorization': 'Bearer $newToken',
              'Accept': 'application/json',
            },
          );
          if (!mounted) return;
        }
      }

      if (resp.statusCode == 200) {
        // Refresh developer mode status from backend
        try {
          final devProvider = Provider.of<DeveloperModeProvider>(context, listen: false);
          devProvider.setBaseUrl(_apiBaseUrl);
          await devProvider.refreshFromBackend();
        } catch (e) {
          debugPrint('⚠️ Could not refresh developer status: $e');
        }
        
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/home');
        return;
      }

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        // Refresh also failed - clear everything
        await prefs.remove('token');
        await prefs.remove('refresh_token');
        // Clear developer mode on logout
        if (mounted) {
          final devProvider = Provider.of<DeveloperModeProvider>(context, listen: false);
          await devProvider.clear();
        }
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }

      String msg = 'Auth check failed (HTTP ${resp.statusCode})';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['detail'] != null) {
          msg = decoded['detail'].toString();
        }
      } catch (_) {}

      setState(() {
        _loading = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not connect to server';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                if (_loading) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Checking login…'),
                ] else ...[
                  Text(
                    _error ?? 'Unknown error',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _checkAuth,
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    child: const Text('Go to Login'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
