import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/ai_extraction_result.dart';
import '../services/gemini_service.dart';
import '../services/extraction_parser.dart';
import '../constants/ai_prompts.dart';

/// Status of the AI extractor workflow.
enum AIExtractorStatus { idle, extracting, done, error }

/// State management for the AI Extractor feature (Gemini API backend).
///
/// Tracks selected images, API key status, extraction progress, and results.
class AIExtractorProvider extends ChangeNotifier {
  AIExtractorStatus _status = AIExtractorStatus.idle;
  final List<File> _selectedImages = [];
  List<AIExtractionResult> _results = [];
  String? _errorMessage;
  int _currentImageIndex = 0;
  int _totalImages = 0;

  /// True when a Gemini API key is stored in SharedPreferences.
  bool _apiKeyConfigured = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  AIExtractorStatus get status => _status;
  List<File> get selectedImages => List.unmodifiable(_selectedImages);
  List<AIExtractionResult> get results => _results;
  String? get errorMessage => _errorMessage;
  int get currentImageIndex => _currentImageIndex;
  int get totalImages => _totalImages;

  /// True if an API key has been saved (model is "configured").
  bool get modelConfigured => _apiKeyConfigured;

  // ── Compatibility shim (used by AIExtractorScreen) ────────────────────────
  bool get isModelLoaded => _apiKeyConfigured; // Gemini: no local model load step

  // ── API-key management ───────────────────────────────────────────────────

  /// Check whether a Gemini API key is stored and update [modelConfigured].
  Future<void> checkModelConfiguration() async {
    _apiKeyConfigured = await GeminiService.isApiKeyConfigured();
    notifyListeners();
  }

  // ── Image management ─────────────────────────────────────────────────────

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

  // ── Extraction ───────────────────────────────────────────────────────────

  /// Run Gemini extraction across all selected images sequentially.
  ///
  /// [additionalPrompt] is appended to the default prompt if non-empty.
  Future<void> extractTransactions({String additionalPrompt = ''}) async {
    if (_selectedImages.isEmpty) {
      _errorMessage = 'No images selected';
      _status = AIExtractorStatus.error;
      notifyListeners();
      return;
    }

    final apiKey = await GeminiService.loadApiKey();
    if (apiKey == null) {
      _errorMessage = 'Gemini API key not set. Please enter your API key first.';
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

    final gemini = GeminiService(apiKey: apiKey);
    final allResults = <AIExtractionResult>[];

    for (int i = 0; i < _selectedImages.length; i++) {
      _currentImageIndex = i + 1;
      notifyListeners();

      try {
        final rawOutput = await gemini.analyzeImage(
          imagePath: _selectedImages[i].path,
          prompt: prompt,
        );

        debugPrint('Gemini output for image ${i + 1}: $rawOutput');

        final parsed = ExtractionParser.parse(rawOutput);
        allResults.addAll(parsed);
      } catch (e) {
        debugPrint('Error extracting from image ${i + 1}: $e');
        // Surface the last error but continue processing remaining images.
        _errorMessage = 'Image ${i + 1}: $e';
      }
    }

    _results = allResults;

    if (_results.isEmpty) {
      _status = AIExtractorStatus.error;
      _errorMessage ??= 'No transactions could be extracted. Try clearer screenshots.';
    } else {
      _status = AIExtractorStatus.done;
      _errorMessage = null; // clear partial error on success
    }
    notifyListeners();
  }

  /// Reset state back to idle.
  void reset() {
    _status = AIExtractorStatus.idle;
    _selectedImages.clear();
    _results = [];
    _errorMessage = null;
    _currentImageIndex = 0;
    _totalImages = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
