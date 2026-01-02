import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SpreadsheetInfo {
  final String id;
  final String? name;
  final DateTime addedDate;

  SpreadsheetInfo({
    required this.id,
    this.name,
    required this.addedDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'addedDate': addedDate.toIso8601String(),
    };
  }

  factory SpreadsheetInfo.fromJson(Map<String, dynamic> json) {
    return SpreadsheetInfo(
      id: json['id'] as String,
      name: json['name'] as String?,
      addedDate: DateTime.parse(json['addedDate'] as String),
    );
  }
}

class SpreadsheetStorageService {
  static final SpreadsheetStorageService _instance =
      SpreadsheetStorageService._internal();
  factory SpreadsheetStorageService() => _instance;
  SpreadsheetStorageService._internal();

  static const String _key = 'saved_spreadsheets';

  Future<List<SpreadsheetInfo>> getSavedSpreadsheets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList
          .map((json) => SpreadsheetInfo.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading saved spreadsheets: $e');
      return [];
    }
  }

  Future<void> saveSpreadsheet(SpreadsheetInfo spreadsheet) async {
    try {
      final spreadsheets = await getSavedSpreadsheets();
      
      // Check if already exists
      final existingIndex = spreadsheets.indexWhere((s) => s.id == spreadsheet.id);
      if (existingIndex != -1) {
        // Update existing
        spreadsheets[existingIndex] = spreadsheet;
      } else {
        // Add new
        spreadsheets.add(spreadsheet);
      }

      final jsonList = spreadsheets.map((s) => s.toJson()).toList();
      final jsonString = json.encode(jsonList);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonString);
      
      debugPrint('Spreadsheet saved: ${spreadsheet.id}');
    } catch (e) {
      debugPrint('Error saving spreadsheet: $e');
      rethrow;
    }
  }

  Future<void> deleteSpreadsheet(String spreadsheetId) async {
    try {
      final spreadsheets = await getSavedSpreadsheets();
      spreadsheets.removeWhere((s) => s.id == spreadsheetId);

      final jsonList = spreadsheets.map((s) => s.toJson()).toList();
      final jsonString = json.encode(jsonList);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonString);
      
      debugPrint('Spreadsheet deleted: $spreadsheetId');
    } catch (e) {
      debugPrint('Error deleting spreadsheet: $e');
      rethrow;
    }
  }

  Future<SpreadsheetInfo?> getSpreadsheet(String spreadsheetId) async {
    final spreadsheets = await getSavedSpreadsheets();
    try {
      return spreadsheets.firstWhere((s) => s.id == spreadsheetId);
    } catch (e) {
      return null;
    }
  }

  // Save default paid by name
  static const String _defaultPaidByKey = 'default_paid_by_name';

  Future<void> saveDefaultPaidByName(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_defaultPaidByKey, name);
      debugPrint('Default paid by name saved: $name');
    } catch (e) {
      debugPrint('Error saving default paid by name: $e');
      rethrow;
    }
  }

  Future<String?> getDefaultPaidByName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_defaultPaidByKey);
    } catch (e) {
      debugPrint('Error loading default paid by name: $e');
      return null;
    }
  }

  Future<void> clearDefaultPaidByName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_defaultPaidByKey);
      debugPrint('Default paid by name cleared');
    } catch (e) {
      debugPrint('Error clearing default paid by name: $e');
    }
  }
}

