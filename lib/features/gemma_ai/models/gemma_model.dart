import 'package:flutter_gemma/flutter_gemma.dart';

class GemmaModel {
  final String id;
  final String name;
  final String tagline;
  final int approxMB;
  final String url;
  final ModelType modelType;
  final ModelFileType fileType;
  final String huggingFacePage;

  const GemmaModel({
    required this.id,
    required this.name,
    required this.tagline,
    required this.approxMB,
    required this.url,
    required this.modelType,
    required this.fileType,
    required this.huggingFacePage,
  });

  // Filename extracted from URL — used as the model ID in flutter_gemma 0.14.x.
  String get filename => Uri.parse(url).pathSegments.last;

  String get sizeLabel =>
      approxMB >= 1000 ? '${(approxMB / 1000).toStringAsFixed(1)} GB' : '$approxMB MB';
}

const List<GemmaModel> kGemmaCatalog = [
  GemmaModel(
    id: 'gemma3-1b',
    name: 'Compact',
    tagline: 'Fast — works on any phone. Great for getting started.',
    approxMB: 555,
    url: 'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/litert-community/Gemma3-1B-IT',
  ),
  GemmaModel(
    id: 'gemma3n-e2b',
    name: 'Balanced',
    tagline: 'Mobile-optimized — best quality-to-size ratio.',
    approxMB: 3100,
    url: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
  ),
  GemmaModel(
    id: 'gemma3n-e4b',
    name: 'Advanced',
    tagline: 'Best quality — needs 6 GB+ RAM (iPhone 15 Pro Max or newer).',
    approxMB: 4400,
    url: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
    modelType: ModelType.gemmaIt,
    fileType: ModelFileType.task,
    huggingFacePage: 'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview',
  ),
];

const String kDefaultGemmaModelId = 'gemma3-1b';
