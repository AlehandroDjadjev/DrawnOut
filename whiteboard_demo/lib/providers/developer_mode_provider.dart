import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider to manage developer mode state globally
/// Developer mode enables advanced timing controls and debug features
class DeveloperModeProvider extends ChangeNotifier {
  static const String _prefsKey = 'developerModeEnabled';
  static const int _secretTapCount = 7; // Number of taps to toggle dev mode
  
  bool _isEnabled = false;
  int _secretTapCounter = 0;
  DateTime? _lastTapTime;
  
  bool get isEnabled => _isEnabled;
  
  DeveloperModeProvider() {
    _loadState();
  }
  
  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefsKey) ?? false;
    notifyListeners();
  }
  
  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, _isEnabled);
  }
  
  /// Toggle developer mode directly (for settings page)
  Future<void> toggle() async {
    _isEnabled = !_isEnabled;
    await _saveState();
    notifyListeners();
  }
  
  /// Enable developer mode
  Future<void> enable() async {
    if (!_isEnabled) {
      _isEnabled = true;
      await _saveState();
      notifyListeners();
    }
  }
  
  /// Disable developer mode
  Future<void> disable() async {
    if (_isEnabled) {
      _isEnabled = false;
      await _saveState();
      notifyListeners();
    }
  }
  
  /// Handle secret tap gesture to toggle dev mode
  /// Returns true if dev mode was toggled
  bool handleSecretTap() {
    final now = DateTime.now();
    
    // Reset counter if more than 2 seconds since last tap
    if (_lastTapTime != null && 
        now.difference(_lastTapTime!).inMilliseconds > 2000) {
      _secretTapCounter = 0;
    }
    
    _lastTapTime = now;
    _secretTapCounter++;
    
    if (_secretTapCounter >= _secretTapCount) {
      _secretTapCounter = 0;
      _isEnabled = !_isEnabled;
      _saveState();
      notifyListeners();
      return true;
    }
    
    return false;
  }
  
  /// Get remaining taps needed (for UI feedback)
  int get remainingTaps => _secretTapCount - _secretTapCounter;
}
