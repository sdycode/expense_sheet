import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists [ThemeMode] (system / light / dark) and notifies listeners so
/// [MaterialApp] can rebuild.
class ThemePreferenceService extends ChangeNotifier {
  ThemePreferenceService._();
  static final ThemePreferenceService instance = ThemePreferenceService._();

  static const String _key = 'app_theme_mode_v1';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode = _fromStorage(prefs.getString(_key));
      notifyListeners();
    } catch (e) {
      debugPrint('ThemePreferenceService.load: $e');
    }
  }

  static ThemeMode _fromStorage(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _toStorage(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _toStorage(mode));
    } catch (e) {
      debugPrint('ThemePreferenceService.setThemeMode: $e');
    }
  }
}
