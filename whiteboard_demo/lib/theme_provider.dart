import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  bool _highContrast = false;

  bool get isDarkMode => _isDarkMode;
  bool get isHighContrast => _highContrast;

  ThemeProvider() {
    _loadTheme();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveTheme();
    notifyListeners();
  }

  void toggleHighContrast() {
    _highContrast = !_highContrast;
    _saveTheme();
    notifyListeners();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _highContrast = prefs.getBool('highContrast') ?? false;
    notifyListeners();
  }

  void _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', _isDarkMode);
    prefs.setBool('highContrast', _highContrast);
  }

  /// Returns the active [ThemeData], applying high-contrast overrides when enabled.
  ThemeData get themeData {
    final brightness = _isDarkMode ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      colorSchemeSeed: Colors.blue,
      brightness: brightness,
      useMaterial3: true,
    );

    if (!_highContrast) return base;

    // High-contrast overrides
    final scheme = base.colorScheme;
    return base.copyWith(
      colorScheme: _isDarkMode
          ? scheme.copyWith(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
              outline: Colors.white,
            )
          : scheme.copyWith(
              primary: Colors.black,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              outline: Colors.black,
            ),
      dividerTheme: DividerThemeData(
        color: _isDarkMode ? Colors.white54 : Colors.black54,
        thickness: 2,
      ),
      iconTheme: IconThemeData(
        color: _isDarkMode ? Colors.white : Colors.black,
      ),
    );
  }
}
