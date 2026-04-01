import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which sheet is treated as "primary" for single-sheet updates and ordering.
enum ExpensePrimarySheet {
  shared,
  personal;

  static ExpensePrimarySheet fromStorage(String? v) {
    if (v == 'personal') return ExpensePrimarySheet.personal;
    return ExpensePrimarySheet.shared;
  }

  String get storageValue =>
      this == ExpensePrimarySheet.personal ? 'personal' : 'shared';
}

/// Whether new expenses update one sheet or can target both.
enum ExpenseSheetsUpdateMode {
  single,
  both;

  static ExpenseSheetsUpdateMode fromStorage(String? v) {
    if (v == 'single') return ExpenseSheetsUpdateMode.single;
    return ExpenseSheetsUpdateMode.both;
  }

  String get storageValue =>
      this == ExpenseSheetsUpdateMode.single ? 'single' : 'both';
}

/// Per-user (Gmail) prefs for how the add-expense flow writes to shared vs personal sheets.
class ExpenseSettingsStorage {
  ExpenseSettingsStorage._();
  static final ExpenseSettingsStorage instance = ExpenseSettingsStorage._();

  static const String _stemPrimary = 'expense_primary_v1_';
  static const String _stemMode = 'expense_update_mode_v1_';
  static const String _stemSecondaryDefault = 'expense_secondary_cb_default_v1_';

  static String _normalizeEmailKey(String? email) {
    final e = email?.trim().toLowerCase() ?? '';
    if (e.isEmpty) return 'guest';
    return e.replaceAll('@', '_at_').replaceAll('.', '_');
  }

  String _kPrimary(String? email) => '$_stemPrimary${_normalizeEmailKey(email)}';
  String _kMode(String? email) => '$_stemMode${_normalizeEmailKey(email)}';
  String _kSecondaryDefault(String? email) =>
      '$_stemSecondaryDefault${_normalizeEmailKey(email)}';

  Future<ExpensePrimarySheet> getPrimarySheet(String? userEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ExpensePrimarySheet.fromStorage(
        prefs.getString(_kPrimary(userEmail)),
      );
    } catch (e) {
      debugPrint('getPrimarySheet: $e');
      return ExpensePrimarySheet.shared;
    }
  }

  Future<void> setPrimarySheet(
    String? userEmail,
    ExpensePrimarySheet value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrimary(userEmail), value.storageValue);
  }

  Future<ExpenseSheetsUpdateMode> getUpdateMode(String? userEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return ExpenseSheetsUpdateMode.fromStorage(
        prefs.getString(_kMode(userEmail)),
      );
    } catch (e) {
      debugPrint('getUpdateMode: $e');
      return ExpenseSheetsUpdateMode.both;
    }
  }

  Future<void> setUpdateMode(
    String? userEmail,
    ExpenseSheetsUpdateMode value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode(userEmail), value.storageValue);
  }

  /// When [getUpdateMode] is [both], initial state of "also add to other sheet" on the form.
  Future<bool> getSecondaryCheckboxDefaultChecked(String? userEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSecondaryDefault(userEmail)) ?? true;
    } catch (e) {
      debugPrint('getSecondaryCheckboxDefaultChecked: $e');
      return true;
    }
  }

  Future<void> setSecondaryCheckboxDefaultChecked(
    String? userEmail,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSecondaryDefault(userEmail), value);
  }
}
