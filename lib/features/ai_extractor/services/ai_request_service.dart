import 'dart:io';

import 'package:flutter/foundation.dart';

import 'base_api_service.dart';
import 'key_manager.dart';
import 'providers/gemini_service_impl.dart';
import 'providers/sambanova_service.dart';
import 'providers/groq_service_impl.dart';
import 'providers/mistral_service.dart';
import 'providers/cloudflare_service.dart';

// ── Exceptions ────────────────────────────────────────────────────────────────

/// Base exception for any AI provider failure.
class AIProviderException implements Exception {
  final String provider;
  final String message;
  final int? statusCode;

  AIProviderException(this.provider, this.message, {this.statusCode});

  @override
  String toString() => '[$provider] $message';
}

/// Thrown when the provider rate-limits (HTTP 429) or is overloaded (HTTP 503).
class QuotaExceededException extends AIProviderException {
  QuotaExceededException(String provider)
      : super(
          provider,
          'API quota exceeded or service overloaded. '
          'Switching to the next provider automatically.',
          statusCode: 429,
        );
}

/// Thrown when the API key is invalid or revoked (HTTP 401 / 403).
class InvalidApiKeyException extends AIProviderException {
  InvalidApiKeyException(String provider)
      : super(
          provider,
          'Invalid or revoked API key. Please check your settings.',
          statusCode: 401,
        );
}

// ── Provider Models & Cascade ────────────────────────────────────────────────

/// Canonical model strings for each provider.
/// First entry is the default model used when [selectedModel] is null.
const Map<String, List<String>> kProviderModels = {
  'gemini': ['gemini-1.5-flash', 'gemini-2.0-flash-exp'],
  'sambanova': ['Llama-3.2-11B-Vision-Instruct', 'Llama-3.2-90B-Vision-Instruct'],
  'groq': ['llama-3.2-90b-vision-preview', 'llama-3.2-11b-vision-preview'],
  'mistral': ['pixtral-12b-2409', 'pixtral-large-2411'],
  'cloudflare': ['@cf/meta/llama-3.2-11b-vision-instruct'],
};

/// The priority order in which providers will be tried.
/// On 429 / 503 the entire provider is skipped to the next in this list.
const List<String> kProviderCascade = [
  'gemini',
  'sambanova',
  'groq',
  'mistral',
  'cloudflare',
];

// ── AIRequestService ──────────────────────────────────────────────────────────

/// Unified AI request service with **multi-provider cascade** and
/// **per-provider key rotation + retry**.
///
/// ### Adding a new provider
/// 1. Create a class implementing [BaseApiService] in `services/providers/`.
/// 2. Add it to [_registry] below.
/// 3. Add its ID to [kProviderCascade] and [kProviderModels].
/// 4. Add its ID to [kSupportedProviders] in `key_manager.dart`.
/// That's it — no other files need modification.
class AIRequestService {
  AIRequestService._();

  // Maximum key-rotation attempts within a single provider before cascading.
  static const int _maxRetriesPerProvider = 3;

  // ── Service registry ──────────────────────────────────────────────────────

  /// Map of provider ID → [BaseApiService] implementation.
  /// To add a new provider, insert one entry here.
  static final Map<String, BaseApiService> _registry = {
    'gemini': const GeminiServiceImpl(),
    'sambanova': SambanovaService(),
    'groq': GroqServiceImpl(),
    'mistral': MistralService(),
    'cloudflare': CloudflareService(),
  };

  // ── Public entry point ────────────────────────────────────────────────────

  /// Analyze [imageFile] using [prompt].
  ///
  /// If [selectedProvider] is set, only that provider is tried
  /// (with up to [_maxRetriesPerProvider] key rotations).
  ///
  /// Otherwise, the full [kProviderCascade] is attempted in order.
  /// On **429 or 503** the current provider is abandoned immediately and
  /// the next one in the cascade is tried — no further retries on that provider.
  ///
  /// On success, increments the user's hit count in Firebase.
  static Future<String> analyzeImage({
    required File imageFile,
    required String prompt,
    String? selectedProvider,
    String? selectedModel,
  }) async {
    final providers = selectedProvider != null
        ? [selectedProvider]
        : kProviderCascade;

    AIProviderException? lastError;

    for (final providerId in providers) {
      final service = _registry[providerId];
      if (service == null) {
        debugPrint('AIRequestService: unknown provider "$providerId" — skipping');
        continue;
      }

      try {
        final result = await _callWithRetry(
          service: service,
          imageFile: imageFile,
          prompt: prompt,
          preferredModel: selectedModel,
        );
        await KeyManager.instance.incrementHitCount();
        return result;
      } on NoAvailableKeyException catch (e) {
        debugPrint('AIRequestService: [$providerId] no keys — skipping. $e');
        lastError = AIProviderException(providerId, 'No API keys configured.');
        // No key at all → cascade to next provider immediately
      } on QuotaExceededException catch (e) {
        debugPrint('AIRequestService: [$providerId] rate-limited/overloaded — cascading. $e');
        lastError = e;
        // 429 / 503 → cascade to next provider immediately
      } on InvalidApiKeyException catch (e) {
        debugPrint('AIRequestService: [$providerId] invalid key — cascading. $e');
        lastError = e;
        // Bad key also cascades (user should fix via settings)
      } on AIProviderException catch (e) {
        debugPrint('AIRequestService: [$providerId] provider error — $e');
        lastError = e;
      } catch (e) {
        debugPrint('AIRequestService: [$providerId] unexpected error — $e');
        lastError = AIProviderException(providerId, e.toString());
      }
    }

    throw lastError ??
        AIProviderException(
          'All Providers',
          'All AI providers were exhausted. Please check your API keys in Settings.',
        );
  }

  // ── Per-provider retry wrapper ────────────────────────────────────────────

  /// Retries up to [_maxRetriesPerProvider] times within a single provider,
  /// rotating to a new key on each [QuotaExceededException] or
  /// [InvalidApiKeyException].
  ///
  /// If the error is 429 / 503 (quota / overloaded), rethrows immediately
  /// so the caller cascades to the next provider.
  static Future<String> _callWithRetry({
    required BaseApiService service,
    required File imageFile,
    required String prompt,
    String? preferredModel,
  }) async {
    final providerId = service.providerId;
    final model =
        preferredModel ?? kProviderModels[providerId]?.first ?? providerId;

    String? currentKey;

    for (int attempt = 0; attempt < _maxRetriesPerProvider; attempt++) {
      try {
        currentKey = await KeyManager.instance.getBestAvailableKey(providerId);
        debugPrint(
          'AIRequestService: [$providerId] attempt ${attempt + 1}/$_maxRetriesPerProvider '
          'model=$model',
        );
        return await service.analyzeImage(
          imageFile: imageFile,
          prompt: prompt,
          apiKey: currentKey,
          model: model,
        );
      } on QuotaExceededException {
        // 429/503 — report the key failure then rethrow so cascade kicks in
        if (currentKey != null) {
          KeyManager.instance.reportKeyFailure(currentKey, providerId);
        }
        rethrow; // cascade immediately; no more retries for this provider
      } on InvalidApiKeyException {
        // Bad key — rotate and retry (up to limit); then rethrow
        if (currentKey != null) {
          KeyManager.instance.reportKeyFailure(currentKey, providerId);
        }
        if (attempt == _maxRetriesPerProvider - 1) rethrow;
      }
      // Any other exception propagates to analyzeImage which logs & cascades
    }

    throw AIProviderException(providerId, 'Max retries reached for $providerId');
  }
}
