import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';

/// Provider to manage developer mode state globally
/// 
/// Developer mode is controlled by the `is_developer` flag on the user's
/// backend profile. Only users manually marked as developers in the database
/// can access debug features like the developer panel.
class DeveloperModeProvider extends ChangeNotifier {
  static const String _cachedDevFlagKey = 'cachedIsDeveloper';
  
  bool _isEnabled = false;
  bool _isLoading = true;
  String? _baseUrl;
  
  bool get isEnabled => _isEnabled;
  bool get isLoading => _isLoading;
  
  DeveloperModeProvider() {
    _loadCachedState();
  }
  
  /// Set the API base URL (call this after app config is loaded)
  void setBaseUrl(String url) {
    _baseUrl = url.trim();
    if (_baseUrl!.endsWith('/')) {
      _baseUrl = _baseUrl!.substring(0, _baseUrl!.length - 1);
    }
  }
  
  /// Load cached developer state from local storage
  Future<void> _loadCachedState() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_cachedDevFlagKey) ?? false;
    _isLoading = false;
    notifyListeners();
  }
  
  /// Cache the developer state locally
  Future<void> _cacheState(bool isDeveloper) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cachedDevFlagKey, isDeveloper);
  }
  
  /// Refresh developer status from backend profile.
  /// 
  /// Uses AuthService for automatic token refresh on 401.
  /// Call this after login or when the app starts to sync with backend.
  /// Returns true if the user is a developer.
  Future<bool> refreshFromBackend() async {
    if (_baseUrl == null) {
      debugPrint('⚠️ DeveloperModeProvider: baseUrl not set');
      return _isEnabled;
    }
    
    try {
      final authService = AuthService(baseUrl: _baseUrl!);
      
      final resp = await authService.authenticatedGet(
        '$_baseUrl/api/auth/profile/',
      );
      
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final isDeveloper = data['is_developer'] == true;
        
        _isEnabled = isDeveloper;
        await _cacheState(isDeveloper);
        _isLoading = false;
        notifyListeners();
        
        debugPrint('🔧 Developer mode: ${isDeveloper ? 'ENABLED' : 'disabled'}');
        return isDeveloper;
      } else {
        debugPrint('⚠️ Profile fetch failed: ${resp.statusCode}');
        _isLoading = false;
        notifyListeners();
        return _isEnabled;
      }
    } catch (e) {
      debugPrint('⚠️ Developer mode check failed: $e');
      _isLoading = false;
      notifyListeners();
      return _isEnabled;
    }
  }
  
  /// Clear developer status (call on logout)
  Future<void> clear() async {
    _isEnabled = false;
    await _cacheState(false);
    notifyListeners();
  }
}
