import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the Gemini API key.
const String kPrefGeminiApiKey = 'gemini_api_key';

/// Default Gemini model to use.
/// gemini-2.5-flash is shown to have free-tier access (5 RPM) in your account.
const String kGeminiModel = 'gemini-2.5-flash';

/// Service that sends images to the Gemini API and returns raw text.
///
/// Usage:
/// ```dart
/// final svc = GeminiService(apiKey: 'YOUR_API_KEY');
/// final text = await svc.analyzeImage(imagePath: '/path/to/img.jpg', prompt: '...');
/// ```
class GeminiService {
  final String apiKey;

  GeminiService({required this.apiKey});

  // ── Static helpers ────────────────────────────────────────────────────────

  /// Persist the API key to SharedPreferences.
  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefGeminiApiKey, key.trim());
  }

  /// Retrieve the stored API key, or null if not yet set.
  static Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(kPrefGeminiApiKey);
    if (key == null || key.isEmpty) return null;
    return key;
  }

  /// Remove the stored API key.
  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefGeminiApiKey);
  }

  /// Returns true when an API key is saved.
  static Future<bool> isApiKeyConfigured() async {
    final key = await loadApiKey();
    return key != null && key.isNotEmpty;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  /// Send [imagePath] + [prompt] to Gemini and return the raw response text.
  ///
  /// Throws on network error or API error.
  Future<String> analyzeImage({
    required String imagePath,
    required String prompt,
  }) async {
    final model = GenerativeModel(
      model: kGeminiModel,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1, // low temperature → deterministic JSON output
        maxOutputTokens: 4096,
      ),
    );

    final Uint8List imageBytes = await File(imagePath).readAsBytes();
    final mimeType = _mimeType(imagePath);

    debugPrint(
      'GeminiService: Sending image (${imageBytes.length} bytes) to $kGeminiModel',
    );

    final response = await model.generateContent([
      Content.multi([DataPart(mimeType, imageBytes), TextPart(prompt)]),
    ]);

    final text = response.text;
    if (text == null || text.isEmpty) {
      throw Exception(
        'Gemini returned an empty response. Check your API key and try again.',
      );
    }

    debugPrint('GeminiService: Response length = ${text.length}');
    return text;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Determine MIME type from file extension.
  static String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg'; // default for .jpg / .jpeg
  }
}
