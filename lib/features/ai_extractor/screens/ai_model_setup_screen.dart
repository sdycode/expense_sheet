import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/llm_service.dart' show LlmService, isPlatformSupported;

/// One-time setup screen for picking the moondream2 model files.
///
/// Users select the text-model GGUF and vision-projector GGUF. Both paths
/// are persisted via [SharedPreferences] so the model can be loaded later.
class AIModelSetupScreen extends StatefulWidget {
  const AIModelSetupScreen({super.key});

  @override
  State<AIModelSetupScreen> createState() => _AIModelSetupScreenState();
}

class _AIModelSetupScreenState extends State<AIModelSetupScreen> {
  String? _textModelPath;
  String? _mmprojPath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingPaths();
  }

  Future<void> _loadExistingPaths() async {
    final paths = await LlmService.getModelPaths();
    if (mounted) {
      setState(() {
        _textModelPath = paths.textPath;
        _mmprojPath = paths.mmprojPath;
      });
    }
  }

  Future<void> _pickFile({required bool isTextModel}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      dialogTitle: isTextModel
          ? 'Select text model (.gguf)'
          : 'Select vision projector (.gguf)',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        if (isTextModel) {
          _textModelPath = result.files.single.path;
        } else {
          _mmprojPath = result.files.single.path;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_textModelPath == null || _mmprojPath == null) return;

    setState(() => _isSaving = true);

    try {
      await LlmService.saveModelPaths(
        textPath: _textModelPath!,
        mmprojPath: _mmprojPath!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Model paths saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // true = paths updated
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving paths: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guard: native library not available on Android
    if (!isPlatformSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('AI Model Setup')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.android, size: 56, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Not available on Android',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The AI model requires libmtmd.so (llama.cpp NDK build). '
                  'Please use this feature on iOS or desktop.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final bothSet = _textModelPath != null && _mmprojPath != null;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Model Setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Header ──
          Icon(
            Icons.smart_toy_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Configure Moondream 2',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Select the two GGUF model files from your device.\n'
            'These files are needed for on-device AI extraction.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // ── Text model picker ──
          _FilePickerTile(
            title: 'Text Model',
            subtitle: 'moondream2-text-model-f16.gguf',
            filePath: _textModelPath,
            onPick: () => _pickFile(isTextModel: true),
          ),

          const SizedBox(height: 14),

          // ── Projector picker ──
          _FilePickerTile(
            title: 'Vision Projector',
            subtitle: 'moondream2-mmproj-f16.gguf',
            filePath: _mmprojPath,
            onPick: () => _pickFile(isTextModel: false),
          ),

          const SizedBox(height: 28),

          // ── Status indicator ──
          if (bothSet)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Both files selected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // ── Save button ──
          FilledButton.icon(
            onPressed: bothSet && !_isSaving ? _save : null,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Save Model Paths'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePickerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? filePath;
  final VoidCallback onPick;

  const _FilePickerTile({
    required this.title,
    required this.subtitle,
    required this.filePath,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSet = filePath != null;
    final fileName = isSet ? filePath!.split('/').last : 'Not selected';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(
          isSet ? Icons.check_circle : Icons.file_open_outlined,
          color: isSet ? Colors.green : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              fileName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSet ? FontWeight.w600 : FontWeight.normal,
                color: isSet
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        trailing: TextButton(
          onPressed: onPick,
          child: Text(isSet ? 'Change' : 'Pick'),
        ),
      ),
    );
  }
}
