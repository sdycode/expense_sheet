import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_extraction_result.dart';
import '../services/ai_request_service.dart';
import '../services/extraction_parser.dart';
import '../constants/ai_prompts.dart';
import '../services/key_manager.dart';

/// Status of the AI extractor workflow.
enum AIExtractorStatus { idle, extracting, done, error }

/// State management for the AI Extractor feature.
class AIExtractorProvider extends ChangeNotifier {
  AIExtractorStatus _status = AIExtractorStatus.idle;
  final List<File> _selectedImages = [];
  List<AIExtractionResult> _results = [];
  String? _errorMessage;
  int _currentImageIndex = 0;
  int _totalImages = 0;

  bool _apiKeyConfigured = false;
  String? _preferredProvider; // null = auto
  String? _preferredModel;

  // ── Getters ───────────────────────────────────────────────────────────────

  AIExtractorStatus get status => _status;
  List<File> get selectedImages => List.unmodifiable(_selectedImages);
  List<AIExtractionResult> get results => _results;
  String? get errorMessage => _errorMessage;
  int get currentImageIndex => _currentImageIndex;
  int get totalImages => _totalImages;
  bool get modelConfigured => _apiKeyConfigured;
  String? get preferredProvider => _preferredProvider;
  String? get preferredModel => _preferredModel;

  Future<void> init() async {
    await checkModelConfiguration();
  }

  Future<void> checkModelConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    _preferredProvider = prefs.getString('preferred_ai_provider');
    _preferredModel = prefs.getString('preferred_ai_model');

    // Check RTDB for any provider key
    bool anyKey = false;
    for (final p in kSupportedProviders) {
      if (await KeyManager.instance.isAnyKeyConfigured(p)) {
        anyKey = true;
        break;
      }
    }

    if (anyKey) {
      _apiKeyConfigured = true;
    } else {
      // Legacy fallback
      final legacyKey = prefs.getString('gemini_api_key') ?? '';
      _apiKeyConfigured = legacyKey.isNotEmpty;
    }
    notifyListeners();
  }

  Future<void> setPreferredAI(String? provider, String? model) async {
    final prefs = await SharedPreferences.getInstance();
    _preferredProvider = provider;
    _preferredModel = model;
    if (provider == null) {
      await prefs.remove('preferred_ai_provider');
      await prefs.remove('preferred_ai_model');
    } else {
      await prefs.setString('preferred_ai_provider', provider);
      if (model != null) {
        await prefs.setString('preferred_ai_model', model);
      } else {
        await prefs.remove('preferred_ai_model');
      }
    }
    notifyListeners();
  }

  // ── Image management ──────────────────────────────────────────────────────

  void addImages(List<File> images) {
    _selectedImages.addAll(images);
    notifyListeners();
  }

  void removeImageAt(int index) {
    if (index >= 0 && index < _selectedImages.length) {
      _selectedImages.removeAt(index);
      notifyListeners();
    }
  }

  void clearImages() {
    _selectedImages.clear();
    notifyListeners();
  }

  // ── Extraction ────────────────────────────────────────────────────────────

  Future<void> extractTransactions({String additionalPrompt = ''}) async {
    if (_selectedImages.isEmpty) {
      _errorMessage = 'No images selected';
      _status = AIExtractorStatus.error;
      notifyListeners();
      return;
    }

    _status = AIExtractorStatus.extracting;
    _results = [];
    _errorMessage = null;
    _totalImages = _selectedImages.length;
    _currentImageIndex = 0;
    notifyListeners();

    final prompt = additionalPrompt.trim().isEmpty
        ? kDefaultExtractionPrompt
        : '$kDefaultExtractionPrompt\n\nAdditional instructions: $additionalPrompt';

    final allResults = <AIExtractionResult>[];

    for (int i = 0; i < _selectedImages.length; i++) {
      _currentImageIndex = i + 1;
      notifyListeners();

      try {
        final rawOutput = await AIRequestService.analyzeImage(
          imageFile: _selectedImages[i],
          prompt: prompt,
          selectedProvider: _preferredProvider,
          selectedModel: _preferredModel,
        );

        debugPrint('AI Output: $rawOutput');
        final parsed = ExtractionParser.parse(rawOutput);
        allResults.addAll(parsed);
      } on AIProviderException catch (e) {
        _errorMessage = e.toString();
        debugPrint('AIProviderException: $e');
        // Stop on quota or auth errors to prevent infinite loops or burning other keys pointlessly
        if (e is QuotaExceededException || e is InvalidApiKeyException) {
          break;
        }
      } catch (e) {
        _errorMessage = 'Generic Error: $e';
      }
    }

    _results = allResults;
    if (_results.isEmpty) {
      _status = AIExtractorStatus.error;
      _errorMessage ??= 'No transactions found. Try again with clearer images.';
    } else {
      _status = AIExtractorStatus.done;
      _errorMessage = null;
    }
    notifyListeners();
  }

  void reset() {
    _status = AIExtractorStatus.idle;
    _selectedImages.clear();
    _results = [];
    _errorMessage = null;
    _currentImageIndex = 0;
    _totalImages = 0;
    notifyListeners();
  }
}
