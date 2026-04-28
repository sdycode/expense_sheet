import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gemma_model.dart';
import '../services/gemma_service.dart';
import '../services/hf_token_service.dart';

class GemmaProvider extends ChangeNotifier {
  static final GemmaProvider instance = GemmaProvider._();
  GemmaProvider._();

  static const _selectedModelKey = 'gemma_selected_model_id';
  static const _aiDisabledKey = 'gemma_ai_disabled';

  final _service = GemmaService();

  // Tracks install state per model.id — the single source of truth for UI.
  final Map<String, bool> _installStates = {};

  GemmaModel _selectedModel = kGemmaCatalog.first;
  bool _isAnyInstalled = false;
  bool _isCheckingInstall = false;
  bool _aiDisabled = false;
  bool _initDone = false;

  // Download state
  bool _isDownloading = false;
  GemmaModel? _downloadingModel;
  double _downloadProgress = 0;

  // Error state — persists after download finishes so the card can still show it.
  // Cleared only when a new download starts.
  GemmaModel? _lastErrorModel;
  String? _downloadError;
  GemmaAuthException? _authException;

  // ── Getters ──────────────────────────────────────────────────────────────

  GemmaModel get selectedModel => _selectedModel;
  bool get isAnyInstalled => _isAnyInstalled;
  bool get isCheckingInstall => _isCheckingInstall;
  bool get aiDisabled => _aiDisabled;
  bool get isDownloading => _isDownloading;
  GemmaModel? get downloadingModel => _downloadingModel;
  double get downloadProgress => _downloadProgress;
  GemmaModel? get lastErrorModel => _lastErrorModel;
  String? get downloadError => _downloadError;
  GemmaAuthException? get authException => _authException;

  // Per-model install state — always accurate after any install/delete/refresh.
  bool isInstalledFor(String modelId) => _installStates[modelId] ?? false;

  // ── Init ─────────────────────────────────────────────────────────────────

  // Safe to call on every screen open — full init runs once, subsequent calls
  // just refresh install states (no repeated Firebase calls).
  Future<void> init() async {
    if (!_initDone) {
      final prefs = await SharedPreferences.getInstance();
      _aiDisabled = prefs.getBool(_aiDisabledKey) ?? false;
      final savedId = prefs.getString(_selectedModelKey) ?? kDefaultGemmaModelId;
      _selectedModel = kGemmaCatalog.firstWhere(
        (m) => m.id == savedId,
        orElse: () => kGemmaCatalog.first,
      );
      final token = await HfTokenService.fetchAndCache();
      await _service.initializeWithToken(token);
      _initDone = true;
      notifyListeners();
    }
    await refreshInstallState();
  }

  Future<void> refreshInstallState() async {
    _isCheckingInstall = true;
    notifyListeners();
    for (final m in kGemmaCatalog) {
      _installStates[m.id] = await _service.isInstalled(m);
    }
    _isAnyInstalled = _installStates.values.any((v) => v);
    _isCheckingInstall = false;
    notifyListeners();
  }

  // ── Model selection ───────────────────────────────────────────────────────

  Future<void> selectModel(GemmaModel m) async {
    if (_selectedModel.id == m.id) return;
    _selectedModel = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedModelKey, m.id);
    notifyListeners();
  }

  Future<void> setAiDisabled(bool value) async {
    _aiDisabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiDisabledKey, value);
    if (value) {
      try { await _service.unload(); } catch (_) {}
    }
    notifyListeners();
  }

  // ── Install / Delete ──────────────────────────────────────────────────────

  Future<void> installModel(GemmaModel m) async {
    if (_isDownloading) return;
    _isDownloading = true;
    _downloadingModel = m;
    _downloadProgress = 0;
    // Clear any previous error — new attempt starting.
    _lastErrorModel = null;
    _downloadError = null;
    _authException = null;
    notifyListeners();

    try {
      final token = await HfTokenService.getCached();
      await _service.install(
        m,
        huggingFaceToken: token,
        onProgress: (fraction) {
          _downloadProgress = fraction;
          notifyListeners();
        },
      );
      // Success — update install state immediately (don't wait for refreshInstallState).
      _installStates[m.id] = true;
      _isAnyInstalled = true;
      // Auto-select the model the user just downloaded.
      _selectedModel = m;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, m.id);
    } on GemmaAuthException catch (e) {
      _lastErrorModel = m;
      _authException = e;
      _downloadError = 'auth';
    } catch (e) {
      _lastErrorModel = m;
      _downloadError = _humanError(e.toString());
    } finally {
      _isDownloading = false;
      _downloadingModel = null;
      // _lastErrorModel / _downloadError / _authException intentionally kept
      // so the card can still render the error after this notifyListeners().
      notifyListeners();
    }
  }

  Future<void> deleteModel(GemmaModel m) async {
    await _service.delete(m);
    _installStates[m.id] = false;
    if (_selectedModel.id == m.id) {
      // Auto-switch selection to another installed model if one exists.
      final other = kGemmaCatalog.firstWhere(
        (other) => other.id != m.id && (_installStates[other.id] ?? false),
        orElse: () => kGemmaCatalog.first,
      );
      _selectedModel = other;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedModelKey, other.id);
    }
    _isAnyInstalled = _installStates.values.any((v) => v);
    notifyListeners();
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  Future<String> generate({
    required String prompt,
    String? instructions,
    GemmaModel? model,
  }) {
    return _service.generate(
      model: model ?? _selectedModel,
      prompt: prompt,
      instructions: instructions,
    );
  }

  Future<String> chat({
    required List<Map<String, String>> messages,
    String? instructions,
    GemmaModel? model,
  }) {
    return _service.chat(
      model: model ?? _selectedModel,
      messages: messages,
      instructions: instructions,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _humanError(String raw) {
    final s = raw.toLowerCase();
    if (s.contains('timeout') || s.contains('timed out')) {
      return 'Download is taking too long. Check your Wi-Fi and try again.';
    }
    if (s.contains('socket') || s.contains('connection') ||
        s.contains('host lookup') || s.contains('unreachable') ||
        s.contains('network')) {
      return 'No internet connection. Make sure Wi-Fi is on, then retry.';
    }
    if (s.contains('space') || s.contains('enospc') || s.contains('storage')) {
      return 'Not enough storage on this device.';
    }
    if (s.contains('404') || s.contains('not found')) {
      return 'This model isn\'t available right now. Pick another option.';
    }
    return 'Download didn\'t finish. Tap Retry.';
  }
}
