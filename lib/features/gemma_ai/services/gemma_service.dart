import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/gemma_model.dart';

class GemmaAuthException implements Exception {
  final String acceptLicenseUrl;
  const GemmaAuthException(this.acceptLicenseUrl);
  @override
  String toString() => 'GemmaAuthException: accept license at $acceptLicenseUrl';
}

class GemmaService {
  static final GemmaService _instance = GemmaService._();
  factory GemmaService() => _instance;
  GemmaService._();

  bool _initialized = false;
  InferenceModel? _model;
  String? _loadedModelId;

  // Serialises all inference — two concurrent generate/chat calls trip the
  // MediaPipe engine with "AddQueryChunk should not be called before PredictDone".
  Future<dynamic> _inferenceChain = Future<void>.value();

  Future<T> _runSerialised<T>(Future<T> Function() op) {
    final next = _inferenceChain.then((_) => op());
    _inferenceChain = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  // Must be called once with the HF token before any other operation.
  // ServiceRegistry.initialize() is idempotent — subsequent calls are ignored,
  // so call this as early as possible (ideally in main() before runApp).
  Future<void> initializeWithToken(String? token) async {
    if (_initialized) return;
    try {
      // Register background_downloader's Dart method-channel handler before
      // FlutterGemma starts any download. Without this, Android's TaskRunner
      // fires progress events before the handler exists → "Flutter method not
      // implemented" logged on every tick.
      await FileDownloader().configure();
      await FlutterGemma.initialize(
        huggingFaceToken: (token ?? '').isEmpty ? null : token,
      );
      _initialized = true;
    } catch (e, st) {
      debugPrint('[GemmaService.initializeWithToken] $e\n$st');
    }
  }

  Future<bool> isInstalled(GemmaModel m) async {
    try {
      return await FlutterGemma.isModelInstalled(m.filename);
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAnyInstalled() async {
    for (final m in kGemmaCatalog) {
      if (await isInstalled(m)) return true;
    }
    return false;
  }

  // Installs the model from network. Already-installed models skip download.
  // onProgress receives 0.0–1.0 fraction.
  Future<void> install(
    GemmaModel m, {
    String? huggingFaceToken,
    void Function(double fraction)? onProgress,
  }) async {
    try {
      await FlutterGemma.installModel(
        modelType: m.modelType,
        fileType: m.fileType,
      )
          .fromNetwork(m.url, token: huggingFaceToken)
          .withProgress((int p) => onProgress?.call(p / 100.0))
          .install();
    } catch (e, st) {
      debugPrint('[GemmaService.install] $e\n$st');
      final msg = e.toString().toLowerCase();
      // DownloadException.toString() surfaces "401", "403", or the error title
      // ("authentication required", "access forbidden").
      if (msg.contains('401') ||
          msg.contains('403') ||
          msg.contains('authentication required') ||
          msg.contains('access forbidden') ||
          msg.contains('unauthorized') ||
          msg.contains('forbidden')) {
        throw GemmaAuthException(m.huggingFacePage);
      }
      rethrow;
    }
  }

  Future<void> delete(GemmaModel m) async {
    if (_loadedModelId == m.id) await unload();
    try {
      await FlutterGemma.uninstallModel(m.filename);
    } catch (e) {
      debugPrint('[GemmaService.delete] $e');
    }
  }

  // Loads the model into RAM. Calling install() on an already-installed model
  // skips the download and just sets it as the active spec.
  Future<void> load(GemmaModel m) async {
    if (_model != null && _loadedModelId == m.id) return;
    await unload();
    await FlutterGemma.installModel(modelType: m.modelType, fileType: m.fileType)
        .fromNetwork(m.url) // no download if already installed
        .install();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: PreferredBackend.cpu,
    );
    _loadedModelId = m.id;
  }

  Future<void> unload() async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
    _loadedModelId = null;
  }

  Future<String> generate({
    required GemmaModel model,
    required String prompt,
    String? instructions,
    double temperature = 0.7,
  }) {
    return _runSerialised(() async {
      await load(model);
      InferenceModelSession? session;
      try {
        session = await _model!.createSession(
          temperature: temperature,
          randomSeed: DateTime.now().millisecondsSinceEpoch % 10000,
          topK: 40,
          systemInstruction: instructions,
        );
        final full = (instructions != null && instructions.isNotEmpty)
            ? '$instructions\n\n$prompt'
            : prompt;
        await session.addQueryChunk(Message(text: full, isUser: true));
        return await session.getResponse();
      } catch (e, st) {
        debugPrint('[GemmaService.generate] $e\n$st');
        rethrow;
      } finally {
        try {
          await session?.close();
        } catch (_) {}
      }
    });
  }

  // Sessions carry no history — prior turns are flattened into one prompt.
  Future<String> chat({
    required GemmaModel model,
    required List<Map<String, String>> messages,
    String? instructions,
  }) {
    return _runSerialised(() async {
      await load(model);
      InferenceModelSession? session;
      try {
        session = await _model!.createSession(
          temperature: 0.7,
          randomSeed: DateTime.now().millisecondsSinceEpoch % 10000,
          topK: 40,
          systemInstruction: instructions,
        );
        final last = messages.last['content'] ?? '';
        final prompt = messages.length > 1
            ? 'Conversation so far:\n'
                '${messages.sublist(0, messages.length - 1).map((m) => '${(m['role'] ?? 'user').toUpperCase()}: ${m['content']}').join('\n')}'
                '\n\nUser: $last'
            : last;
        await session.addQueryChunk(Message(text: prompt, isUser: true));
        return await session.getResponse();
      } catch (e, st) {
        debugPrint('[GemmaService.chat] $e\n$st');
        rethrow;
      } finally {
        try {
          await session?.close();
        } catch (_) {}
      }
    });
  }
}
