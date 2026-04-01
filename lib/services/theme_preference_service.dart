import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists [ThemeMode] + shared/personal accent colors and notifies listeners
/// so [MaterialApp] and other widgets can rebuild.
class ThemePreferenceService extends ChangeNotifier {
  ThemePreferenceService._();
  static final ThemePreferenceService instance = ThemePreferenceService._();

  static const String _modeKey = 'app_theme_mode_v1';
  static const String _sharedColorKey = 'app_shared_color_v1';
  static const String _personalColorKey = 'app_personal_color_v1';

  /// Default accent for "shared" sheet context (green family).
  static const Color defaultSharedColor = Color(0xFF2E7D32); // green 800
  /// Default accent for "personal" sheet context (blue family).
  static const Color defaultPersonalColor = Color(0xFF1565C0); // blue 800

  ThemeMode _themeMode = ThemeMode.system;
  Color _sharedColor = defaultSharedColor;
  Color _personalColor = defaultPersonalColor;

  ThemeMode get themeMode => _themeMode;
  Color get sharedColor => _sharedColor;
  Color get personalColor => _personalColor;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _themeMode = _modeFromStorage(prefs.getString(_modeKey));
      _sharedColor =
          _colorFromStorage(prefs.getInt(_sharedColorKey)) ?? defaultSharedColor;
      _personalColor =
          _colorFromStorage(prefs.getInt(_personalColorKey)) ?? defaultPersonalColor;
      notifyListeners();
    } catch (e) {
      debugPrint('ThemePreferenceService.load: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, _modeToStorage(mode));
    } catch (e) {
      debugPrint('ThemePreferenceService.setThemeMode: $e');
    }
  }

  Future<void> setSharedColor(Color color) async {
    if (_sharedColor == color) return;
    _sharedColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_sharedColorKey, color.toARGB32());
    } catch (e) {
      debugPrint('ThemePreferenceService.setSharedColor: $e');
    }
  }

  Future<void> setPersonalColor(Color color) async {
    if (_personalColor == color) return;
    _personalColor = color;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_personalColorKey, color.toARGB32());
    } catch (e) {
      debugPrint('ThemePreferenceService.setPersonalColor: $e');
    }
  }

  static ThemeMode _modeFromStorage(String? v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToStorage(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Color? _colorFromStorage(int? v) {
    if (v == null) return null;
    return Color(v);
  }
}
