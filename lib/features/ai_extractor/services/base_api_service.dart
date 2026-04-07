import 'dart:io';

/// Abstract interface that every provider service implementation must satisfy.
///
/// Adding a new provider simply means:
///   1. Create a class that `implements BaseApiService`.
///   2. Register it in the `AIRequestService._registry` map.
///
/// No other files need to change.
abstract class BaseApiService {
  /// The canonical provider identifier used in Firebase RTDB paths and
  /// matching keys in [kSupportedProviders].
  String get providerId;

  /// Sends [imageFile] + [prompt] to the provider using [apiKey] and [model].
  ///
  /// Returns the raw text response from the model.
  ///
  /// Must throw [QuotaExceededException] on HTTP 429 / 503.
  /// Must throw [InvalidApiKeyException] on HTTP 401 / 403.
  Future<String> analyzeImage({
    required File imageFile,
    required String prompt,
    required String apiKey,
    required String model,
  });
}
