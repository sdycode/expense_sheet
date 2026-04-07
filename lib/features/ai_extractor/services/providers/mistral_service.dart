import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../base_api_service.dart';
import '../ai_request_service.dart';

/// Mistral AI provider implementation (Pixtral vision model).
///
/// Uses the standard Mistral chat completions endpoint at
/// `https://api.mistral.ai/v1/chat/completions`.
///
/// Image is sent as a base64 data URI inside the `image_url` content block,
/// which Pixtral-12B accepts natively.
///
/// Default model: `pixtral-12b-2409`
class MistralService implements BaseApiService {
  MistralService({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

  @override
  String get providerId => 'mistral';

  @override
  Future<String> analyzeImage({
    required File imageFile,
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    final base64Image = base64Encode(await imageFile.readAsBytes());
    final mime = _mimeType(imageFile.path);

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://api.mistral.ai/v1/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$base64Image'},
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'temperature': 0.1,
          'max_tokens': 4096,
        },
      );

      final content = response.data?['choices']?[0]?['message']?['content'];
      if (content == null || (content as String).isEmpty) {
        throw AIProviderException(providerId, 'Empty response from Mistral');
      }
      return content;
    } on DioException catch (e) {
      _handleDioError(e);
      rethrow;
    }
  }

  void _handleDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 429 || status == 503) throw QuotaExceededException(providerId);
    if (status == 401 || status == 403) throw InvalidApiKeyException(providerId);
    throw AIProviderException(
      providerId,
      e.response?.data?.toString() ?? e.message ?? 'Unknown Mistral error',
      statusCode: status,
    );
  }

  static String _mimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
