import 'dart:io';

import 'package:dio/dio.dart';

import '../base_api_service.dart';
import '../ai_request_service.dart';

/// Cloudflare Workers AI provider implementation.
///
/// ## Credential Format
/// The API key stored in Firebase must be in the format:
/// ```
/// accountId|apiToken
/// ```
/// The pipe `|` separates the Cloudflare **Account ID** from the
/// **API Token** (or Global API Key). This is split at runtime.
///
/// ## Endpoint
/// `POST https://api.cloudflare.com/client/v4/accounts/{accountId}/ai/run/{model}`
///
/// ## Image Format
/// Cloudflare Workers AI vision models accept a flat JSON payload where
/// `image` is an array of uint8 integers (raw bytes decoded from the file).
/// The prompt is passed as `prompt` at the top level.
///
/// Default model: `@cf/meta/llama-3.2-11b-vision-instruct`
class CloudflareService implements BaseApiService {
  CloudflareService({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

  @override
  String get providerId => 'cloudflare';

  @override
  Future<String> analyzeImage({
    required File imageFile,
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    // Parse the composite credential
    final parts = apiKey.split('|');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      throw InvalidApiKeyException(providerId);
    }
    final accountId = parts[0].trim();
    final apiToken = parts[1].trim();

    // Read image as raw byte list (Cloudflare requires uint8 array)
    final bytes = await imageFile.readAsBytes();
    final imageArray = bytes.toList();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://api.cloudflare.com/client/v4/accounts/$accountId/ai/run/$model',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiToken',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'image': imageArray,
          'prompt': prompt,
          'max_tokens': 4096,
        },
      );

      // Cloudflare Workers AI response: { "result": { "response": "..." }, "success": true }
      final result = response.data?['result'];
      final text = result?['response'] as String?;
      if (text == null || text.isEmpty) {
        throw AIProviderException(providerId, 'Empty response from Cloudflare Workers AI');
      }
      return text;
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
      e.response?.data?.toString() ?? e.message ?? 'Unknown Cloudflare error',
      statusCode: status,
    );
  }
}
