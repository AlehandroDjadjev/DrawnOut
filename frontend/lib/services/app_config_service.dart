import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central configuration service for app settings
class AppConfigService extends ChangeNotifier {
  static const String _backendUrlKey = 'backendUrl';
  static const String _defaultBackendUrl = 'http://127.0.0.1:8000';
  
  String _backendUrl = _defaultBackendUrl;
  
  String get backendUrl => _backendUrl;
  
  /// Default backend URL
  static String get defaultUrl => _defaultBackendUrl;
  
  AppConfigService() {
    _loadConfig();
  }
  
  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString(_backendUrlKey) ?? _defaultBackendUrl;
    notifyListeners();
  }
  
  /// Update the backend URL
  Future<void> setBackendUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    
    // Remove trailing slash
    _backendUrl = trimmed.endsWith('/') 
        ? trimmed.substring(0, trimmed.length - 1) 
        : trimmed;
    
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
