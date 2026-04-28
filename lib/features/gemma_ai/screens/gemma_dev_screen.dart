import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gemma_model.dart';
import '../providers/gemma_provider.dart';
import '../services/gemma_service.dart';
import '../services/hf_token_service.dart';
import '../utils/dev_mode.dart';

// Dev-only screen — shows raw token, model IDs, install state, test prompts.
// Only reachable when devMode == true. Never link to this from production UI.
class GemmaDevScreen extends StatefulWidget {
  const GemmaDevScreen({super.key});

  @override
  State<GemmaDevScreen> createState() => _GemmaDevScreenState();
}

class _GemmaDevScreenState extends State<GemmaDevScreen> {
  final _provider = GemmaProvider.instance;
  String _token = '';
  String _testPrompt = 'Hello! What can you do?';
  String _testResponse = '';
  bool _isTesting = false;
  Map<String, bool> _installState = {};

  @override
  void initState() {
    super.initState();
    assert(devMode, 'GemmaDevScreen must only be used when devMode is true');
    _provider.addListener(_rebuild);
    _loadToken();
    _refreshInstallState();
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadToken() async {
    final t = await HfTokenService.getCached();
    if (mounted) setState(() => _token = t ?? '(none cached)');
  }

  Future<void> _fetchTokenFromFirebase() async {
    setState(() => _token = 'Fetching…');
    final t = await HfTokenService.fetchAndCache();
    if (mounted) setState(() => _token = t.isEmpty ? '(empty)' : t);
  }

  Future<void> _refreshInstallState() async {
    final results = <String, bool>{};
    for (final m in kGemmaCatalog) {
      results[m.id] = await GemmaService().isInstalled(m);
    }
    if (mounted) setState(() => _installState = results);
  }

  Future<void> _runTest() async {
    if (_isTesting) return;
    setState(() { _isTesting = true; _testResponse = ''; });
    try {
      final resp = await _provider.generate(
        prompt: _testPrompt,
        instructions: 'You are a helpful assistant. Reply briefly.',
      );
      setState(() => _testResponse = resp);
    } catch (e) {
      setState(() => _testResponse = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Dev Screen'),
        backgroundColor: Colors.deepOrange.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('HF Token'),
          _DevRow(
            label: 'Cached token',
            value: _token,
            onCopy: () => _copy(_token),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _fetchTokenFromFirebase,
            icon: const Icon(Icons.cloud_download_outlined, size: 16),
            label: const Text('Fetch from Firebase RTDB /hftoken'),
          ),

          _section('Models'),
          for (final m in kGemmaCatalog) _ModelDevRow(
            model: m,
            isInstalled: _installState[m.id],
            provider: _provider,
            onRefresh: _refreshInstallState,
          ),

          _section('Inference Test'),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Test prompt',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: _testPrompt)
              ..selection = TextSelection.collapsed(offset: _testPrompt.length),
            onChanged: (v) => _testPrompt = v,
            maxLines: 3,
          ),
          const SizedBox(height: 8),
          Text('Active model: ${_provider.selectedModel.name} '
              '(${_provider.selectedModel.id})',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _isTesting ? null : _runTest,
            child: _isTesting
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Generating…'),
                  ])
                : const Text('Run test prompt'),
          ),
          if (_testResponse.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(_testResponse,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13,
                letterSpacing: 0.5)),
      );
}

class _DevRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onCopy;

  const _DevRow({required this.label, required this.value, this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
        if (onCopy != null)
          IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy',
              onPressed: onCopy),
      ],
    );
  }
}

class _ModelDevRow extends StatelessWidget {
  final GemmaModel model;
  final bool? isInstalled;
  final GemmaProvider provider;
  final VoidCallback onRefresh;

  const _ModelDevRow({
    required this.model,
    required this.isInstalled,
    required this.provider,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = provider.isDownloading &&
        provider.downloadingModel?.id == model.id;
    final isActive = provider.selectedModel.id == model.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: isActive ? Colors.blue : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: isActive ? Colors.blue.shade50 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${model.id} (${model.name})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12,
                  fontFamily: 'monospace')),
          Text('filename: ${model.filename}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace',
                  color: Colors.grey)),
          Text('size: ${model.sizeLabel}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(
            isInstalled == null
                ? 'checking…'
                : isInstalled!
                    ? '✅ installed'
                    : '⬜ not installed',
            style: const TextStyle(fontSize: 12),
          ),
          if (isDownloading) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: provider.downloadProgress > 0
                  ? provider.downloadProgress
                  : null,
            ),
            Text(
              '${(provider.downloadProgress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 11),
            ),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              if (isInstalled != true && !isDownloading)
                ElevatedButton(
                  onPressed: () => provider
                      .installModel(model)
                      .then((_) => onRefresh()),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(80, 28),
                      textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Download'),
                ),
              if (isInstalled == true)
                ElevatedButton(
                  onPressed: () => provider.selectModel(model),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(80, 28),
                      textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Set Active'),
                ),
              if (isInstalled == true)
                ElevatedButton(
                  onPressed: () async {
                    await provider.deleteModel(model);
                    onRefresh();
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(80, 28),
                      textStyle: const TextStyle(fontSize: 11)),
                  child: const Text('Delete'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
