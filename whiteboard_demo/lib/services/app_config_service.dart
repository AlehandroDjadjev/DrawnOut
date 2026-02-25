import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central configuration service for app settings
class AppConfigService extends ChangeNotifier {
  static const String _backendUrlKey = 'backendUrl';

  static String _stripTrailingSlash(String url) {
    final trimmed = url.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Android emulator cannot reach the host machine at 127.0.0.1/localhost.
  /// Rewrites loopback hosts to 10.0.2.2 so the default config "just works".
  ///
  /// Note: this is applied to *defaults* (env / dart-define) only.
  static String _androidRewriteLoopbackToEmulatorHost(String url) {
    if (kIsWeb || !Platform.isAndroid) return url;

    try {
      final uri = Uri.parse(url);
      if (uri.host == '127.0.0.1' || uri.host == 'localhost') {
        return uri.replace(host: '10.0.2.2').toString();
      }
    } catch (_) {
      // Fall through.
    }

    return url;
  }
  
  /// Get platform-appropriate default URL
  /// Android emulator uses 10.0.2.2 to reach host's localhost
  /// Other platforms use 127.0.0.1
  static String get _defaultBackendUrl {
    // Prefer env-configured backend URL when present.
    // If it points at localhost on Android, rewrite to 10.0.2.2.
    final envUrlRaw = (dotenv.env['API_URL'] ?? '').trim();
    if (envUrlRaw.isNotEmpty) {
      final normalized = _stripTrailingSlash(envUrlRaw);
      return _androidRewriteLoopbackToEmulatorHost(normalized);
    }

    // Also allow compile-time override (e.g. `--dart-define=BACKEND_URL=...`).
    const defined = String.fromEnvironment('BACKEND_URL', defaultValue: '');
    if (defined.trim().isNotEmpty) {
      final v = _stripTrailingSlash(defined);
      return _androidRewriteLoopbackToEmulatorHost(v);
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8001';
    }
    return 'http://127.0.0.1:8001';
  }
  
  late String _backendUrl;
  
  String get backendUrl => _backendUrl;
  
  /// Default backend URL (platform-aware)
  static String get defaultUrl => _defaultBackendUrl;
  
  AppConfigService() {
    _backendUrl = _defaultBackendUrl;
    _loadConfig();
  }
  
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_backendUrlKey);

    // If user previously saved a URL, keep it unless it matches the old default
    // and we now have an environment-provided URL.
    if (saved != null && saved.isNotEmpty) {
      // For saved URLs, preserve exactly what the user entered (aside from a
      // trailing slash) — don't auto-rewrite localhost to 10.0.2.2.
      final normalizedSaved = _stripTrailingSlash(saved);
      final envUrl = (dotenv.env['API_URL'] ?? '').trim();
      final normalizedEnv = envUrl.isEmpty ? '' : _stripTrailingSlash(envUrl);

      const oldDefaults = <String>{
        'http://127.0.0.1:8000',
        'http://localhost:8000',
        'http://10.0.2.2:8000',
      };

      if (normalizedEnv.isNotEmpty && oldDefaults.contains(normalizedSaved)) {
        _backendUrl = _androidRewriteLoopbackToEmulatorHost(normalizedEnv);
        await prefs.setString(_backendUrlKey, _backendUrl);
      } else {
        _backendUrl = normalizedSaved;
      }
    }
    notifyListeners();
  }
  
  /// Update the backend URL
  Future<void> setBackendUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    
    // Remove trailing slash
    _backendUrl = _stripTrailingSlash(trimmed);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendUrlKey, _backendUrl);
    notifyListeners();
  }
  
  /// Reset to default URL
  Future<void> resetToDefault() async {
    _backendUrl = _defaultBackendUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backendUrlKey);
    notifyListeners();
  }
  
  /// Build full API URL
  String apiUrl(String path) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return '$_backendUrl$cleanPath';
  }
}
