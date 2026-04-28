import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HfTokenService {
  static const _prefKey = 'gemma_hf_token';

  // Fetches from Firebase RTDB /hftoken, falls back to SharedPreferences cache.
  static Future<String> fetchAndCache() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('hftoken').get();
      if (snap.exists && snap.value is String) {
        final token = (snap.value as String).trim();
        if (token.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_prefKey, token);
          return token;
        }
      }
    } catch (e, st) {
      debugPrint('[HfTokenService] RTDB fetch failed: $e\n$st');
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? '';
  }

  static Future<String?> getCached() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey);
  }
}
