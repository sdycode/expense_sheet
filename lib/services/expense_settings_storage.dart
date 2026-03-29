import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prefs for home/personal expense UI (checkbox visibility and default).
class ExpenseSettingsStorage {
  ExpenseSettingsStorage._();
  static final ExpenseSettingsStorage instance = ExpenseSettingsStorage._();

  static const String _showHomePersonalToggleKey = 'show_home_personal_toggle';
  static const String _defaultIncludeHomeWhenHiddenKey =
      'default_include_home_when_hidden';

  /// When true, show "Also add to home sheet" on the add-expense form.
  Future<bool> getShowHomePersonalToggle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_showHomePersonalToggleKey) ?? true;
    } catch (e) {
      debugPrint('getShowHomePersonalToggle: $e');
      return true;
    }
  }

  Future<void> setShowHomePersonalToggle(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showHomePersonalToggleKey, value);
  }

  /// When toggle is hidden, this is the effective "also home" value (default true).
  Future<bool> getDefaultIncludeHomeWhenHidden() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_defaultIncludeHomeWhenHiddenKey) ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<void> setDefaultIncludeHomeWhenHidden(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultIncludeHomeWhenHiddenKey, value);
  }
}
