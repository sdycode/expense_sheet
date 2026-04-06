import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/ai_extraction_result.dart';
import '../services/llm_service.dart';
import '../services/extraction_parser.dart';
import '../constants/ai_prompts.dart';

/// Status of the AI extractor workflow.
enum AIExtractorStatus { idle, modelLoading, extracting, done, error }

/// State management for the AI Extractor feature.
///
/// Tracks selected images, model status, extraction progress, and results.
class AIExtractorProvider extends ChangeNotifier {
  AIExtractorStatus _status = AIExtractorStatus.idle;
  final List<File> _selectedImages = [];
  List<AIExtractionResult> _results = [];
  String? _errorMessage;
  int _currentImageIndex = 0;
  int _totalImages = 0;
  bool _modelConfigured = false;

  final LlmService _llmService = LlmService();

  // ── Getters ──

  AIExtractorStatus get status => _status;
  List<File> get selectedImages => List.unmodifiable(_selectedImages);
  List<AIExtractionResult> get results => _results;
  String? get errorMessage => _errorMessage;
  int get currentImageIndex => _currentImageIndex;
  int get totalImages => _totalImages;
  bool get modelConfigured => _modelConfigured;
  bool get isModelLoaded => _llmService.isLoaded;

  // ── Image management ──

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

  // ── Model management ──

  /// Refresh the cached flag indicating whether model paths are stored.
  Future<void> checkModelConfiguration() async {
    _modelConfigured = await LlmService.areModelPathsConfigured();
    notifyListeners();
  }

  /// Load the LLM model into memory.
  Future<void> loadModel() async {
    _status = AIExtractorStatus.modelLoading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _llmService.loadModel();
      _status = AIExtractorStatus.idle;
    } catch (e) {
      _status = AIExtractorStatus.error;
      _errorMessage = 'Failed to load model: $e';
    }
    notifyListeners();
  }

  // ── Extraction ──

  /// Run extraction across all selected images sequentially.
  ///
  /// [additionalPrompt] is appended to the default prompt if non-empty.
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

    // Make sure the model is loaded.
    if (!_llmService.isLoaded) {
      try {
        await _llmService.loadModel();
      } catch (e) {
        _status = AIExtractorStatus.error;
        _errorMessage = 'Could not load model: $e';
        notifyListeners();
        return;
      }
    }

    final prompt = additionalPrompt.trim().isEmpty
        ? kDefaultExtractionPrompt
        : '$kDefaultExtractionPrompt\n\nAdditional instructions: $additionalPrompt';

    final allResults = <AIExtractionResult>[];

    for (int i = 0; i < _selectedImages.length; i++) {
      _currentImageIndex = i + 1;
      notifyListeners();

      try {
        final rawOutput = await _llmService.runInference(
          imagePath: _selectedImages[i].path,
          prompt: prompt,
        );

        debugPrint('LLM output for image ${i + 1}: $rawOutput');

        final parsed = ExtractionParser.parse(rawOutput);
        allResults.addAll(parsed);
      } catch (e) {
        debugPrint('Error extracting from image ${i + 1}: $e');
        // Continue with remaining images rather than aborting.
      }
    }

    _results = allResults;

    if (_results.isEmpty) {
      _status = AIExtractorStatus.error;
      _errorMessage =
          'No transactions could be extracted. Try clearer screenshots.';
    } else {
      _status = AIExtractorStatus.done;
    }
    notifyListeners();
  }

  /// Reset state back to idle, keeping model loaded.
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
    _llmService.dispose();
    super.dispose();
  }
}
