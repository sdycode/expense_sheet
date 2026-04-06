// import 'dart:async';
// import 'dart:io';
// import 'package:flutter/foundation.dart';
// import 'package:llama_cpp_dart/llama_cpp_dart.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// /// Keys used to persist the model file paths across sessions.
// const String kPrefTextModelPath = 'ai_model_text_path';
// const String kPrefMmprojPath = 'ai_model_mmproj_path';

// /// Whether the current platform can run on-device LLM inference.
// ///
// /// `llama_cpp_dart` requires native `.so`/`.dylib` binaries compiled from
// /// source (llama.cpp). On Android, these are shipped inside the APK only
// /// when the project is built from the *full* source repo with NDK support.
// /// When installed via pub.dev, only macOS / iOS / Linux / Windows binaries
// /// are bundled. The feature is therefore disabled on Android until the user
// /// provides pre-built `.so` files.
// bool get isPlatformSupported {
//   if (Platform.isAndroid) return false; // Needs NDK build
//   return true;
// }

// /// Wraps llama_cpp_dart to provide moondream2 multimodal inference.
// ///
// /// Load the model once, run inference on multiple images, then [dispose].
// class LlmService {
//   Llama? _llama;
//   bool _isLoaded = false;

//   bool get isLoaded => _isLoaded;

//   /// Check whether model paths have already been configured.
//   static Future<bool> areModelPathsConfigured() async {
//     if (!isPlatformSupported) return false;
//     final prefs = await SharedPreferences.getInstance();
//     final textPath = prefs.getString(kPrefTextModelPath);
//     final mmprojPath = prefs.getString(kPrefMmprojPath);
//     return textPath != null &&
//         textPath.isNotEmpty &&
//         mmprojPath != null &&
//         mmprojPath.isNotEmpty;
//   }

//   /// Retrieve the stored model paths (may be null).
//   static Future<({String? textPath, String? mmprojPath})>
//   getModelPaths() async {
//     final prefs = await SharedPreferences.getInstance();
//     return (
//       textPath: prefs.getString(kPrefTextModelPath),
//       mmprojPath: prefs.getString(kPrefMmprojPath),
//     );
//   }

//   /// Persist newly chosen model paths.
//   static Future<void> saveModelPaths({
//     required String textPath,
//     required String mmprojPath,
//   }) async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString(kPrefTextModelPath, textPath);
//     await prefs.setString(kPrefMmprojPath, mmprojPath);
//   }

//   /// Load the moondream2 GGUF model files into memory.
//   ///
//   /// Throws if the platform is unsupported or files cannot be loaded.
//   Future<void> loadModel() async {
//     if (_isLoaded) return;

//     if (!isPlatformSupported) {
//       throw UnsupportedError(
//         'On-device AI extraction is not available on Android.\n\n'
//         'The llama.cpp native library must be compiled from source using NDK '
//         'and bundled in the APK. Please use this feature on iOS or desktop.',
//       );
//     }

//     final paths = await getModelPaths();
//     if (paths.textPath == null || paths.mmprojPath == null) {
//       throw Exception('Model paths not configured. Run model setup first.');
//     }

//     try {
//       final modelParams = ModelParams();
//       final contextParams = ContextParams();
//       // Use reasonable context size for mobile/desktop inference.
//       contextParams.nCtx = 2048;

//       _llama = Llama(
//         paths.textPath!,
//         modelParams: modelParams,
//         contextParams: contextParams,
//         // Load multimodal projector for vision input.
//         mmprojPath: paths.mmprojPath!,
//       );
//       _isLoaded = true;
//       debugPrint('LlmService: Model loaded successfully');
//     } catch (e, st) {
//       debugPrint('LlmService: Error loading model: $e\n$st');
//       _isLoaded = false;
//       rethrow;
//     }
//   }

//   /// Run inference on a single image using the given [prompt].
//   ///
//   /// Returns the raw string response from the model.
//   Future<String> runInference({
//     required String imagePath,
//     required String prompt,
//   }) async {
//     if (!_isLoaded || _llama == null) {
//       throw Exception('Model is not loaded. Call loadModel() first.');
//     }

//     try {
//       final StringBuffer response = StringBuffer();

//       // Build the multimodal prompt with image marker.
//       // The <image> marker is replaced internally by the llama_cpp_dart library
//       // with the model-specific image token (e.g. moondream2's <image> token).
//       final imagePrompt = '<image>\n$prompt';

//       final imageInput = LlamaImage.fromFile(File(imagePath));

//       // Use generateWithMedia for multimodal (vision) inference.
//       await for (final token in _llama!.generateWithMedia(
//         imagePrompt,
//         inputs: [imageInput],
//       )) {
//         response.write(token);
//         // Safety cap: stop at ~8k chars to avoid runaway generation.
//         if (response.length > 8000) break;
//       }

//       debugPrint(
//         'LlmService: Inference done, response length: ${response.length}',
//       );
//       return response.toString().trim();
//     } catch (e, st) {
//       debugPrint('LlmService: Inference error: $e\n$st');
//       rethrow;
//     }
//   }

//   /// Release model resources.
//   void dispose() {
//     try {
//       _llama?.dispose();
//     } catch (e) {
//       debugPrint('LlmService: Error disposing model: $e');
//     }
//     _llama = null;
//     _isLoaded = false;
//     debugPrint('LlmService: Model disposed');
//   }
// }
