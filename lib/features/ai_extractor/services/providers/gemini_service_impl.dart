import 'dart:io';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';


import '../base_api_service.dart';
import '../ai_request_service.dart';

/// Gemini (Google AI Studio) provider implementation.
///
/// Uses the official `google_generative_ai` Dart SDK.
/// Sends the image as raw bytes via [DataPart] – no base64 conversion needed.
class GeminiServiceImpl implements BaseApiService {
  const GeminiServiceImpl();

  @override
  String get providerId => 'gemini';

  @override
  Future<String> analyzeImage({
    required File imageFile,
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    try {
      final genModel = GenerativeModel(
        model: model,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.1,
          maxOutputTokens: 4096,
        ),
      );

      final Uint8List bytes = await imageFile.readAsBytes();
      final mime = _mimeType(imageFile.path);

      final response = await genModel.generateContent([
        Content.multi([DataPart(mime, bytes), TextPart(prompt)]),
      ]);

      final text = response.text;
      if (text == null || text.isEmpty) {
        throw AIProviderException(providerId, 'Empty response from model');
      }
      return text;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('429') || msg.contains('resource_exhausted')) {
        throw QuotaExceededException(providerId);
      }
      if (msg.contains('401') || msg.contains('403') || msg.contains('api_key')) {
        throw InvalidApiKeyException(providerId);
      }
      if (e is AIProviderException) rethrow;
      throw AIProviderException(providerId, e.toString());
    }
  }

  static String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
