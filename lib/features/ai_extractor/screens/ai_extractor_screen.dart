import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/ai_extractor_provider.dart';
import '../widgets/image_picker_grid.dart';
import 'ai_model_setup_screen.dart';
import 'ai_results_screen.dart';

/// Main AI Extractor screen (Gemini API backend).
///
/// Top:    API-key status banner (tappable → opens setup if not configured)
/// Middle: image picker + optional additional prompt
/// Bottom: Extract button → navigates to results on success
class AIExtractorScreen extends StatefulWidget {
  /// Spreadsheet IDs needed for saving extracted expenses later.
  final String commonSpreadsheetId;
  final String? personalSpreadsheetId;
  final String? userEmail;
  final String? defaultPaidBy;

  const AIExtractorScreen({
    super.key,
    required this.commonSpreadsheetId,
    this.personalSpreadsheetId,
    this.userEmail,
    this.defaultPaidBy,
  });

  @override
  State<AIExtractorScreen> createState() => _AIExtractorScreenState();
}

class _AIExtractorScreenState extends State<AIExtractorScreen> {
  late final AIExtractorProvider _provider;
  final _additionalPromptController = TextEditingController();
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _provider = AIExtractorProvider();
    _provider.addListener(_onProviderChanged);
    _provider.checkModelConfiguration();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    _provider.dispose();
    _additionalPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _imagePicker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty) {
      _provider.addImages(picked.map((x) => File(x.path)).toList());
    }
  }

  Future<void> _openApiKeySetup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AIModelSetupScreen()),
    );
    if (result == true) {
      await _provider.checkModelConfiguration();
    }
  }

  Future<void> _startExtraction() async {
    await _provider.extractTransactions(
      additionalPrompt: _additionalPromptController.text.trim(),
    );

    if (_provider.status == AIExtractorStatus.done &&
        _provider.results.isNotEmpty &&
        mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AIResultsScreen(
            results: _provider.results,
            commonSpreadsheetId: widget.commonSpreadsheetId,
            personalSpreadsheetId: widget.personalSpreadsheetId,
            userEmail: widget.userEmail ?? '',
            defaultPaidBy: widget.defaultPaidBy ?? '',
          ),
        ),
      );
      // Reset after returning from results.
      _provider.reset();
      _additionalPromptController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExtracting = _provider.status == AIExtractorStatus.extracting;
    final isConfigured = _provider.modelConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Extract'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Gemini API key',
            onPressed: _openApiKeySetup,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── API-key status banner ─────────────────────────────────────────
          _ApiKeyBanner(
            isConfigured: isConfigured,
            onTap: _openApiKeySetup,
          ),
          const SizedBox(height: 18),

          // ── Image picker trigger ──────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: isExtracting ? null : _pickImages,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _provider.selectedImages.isEmpty
                  ? 'Add Images'
                  : 'Add More Images (${_provider.selectedImages.length})',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 12),

          // ── Image grid ────────────────────────────────────────────────────
          ImagePickerGrid(
            images: _provider.selectedImages,
            onRemove: _provider.removeImageAt,
          ),

          if (_provider.selectedImages.isNotEmpty) ...[
            const SizedBox(height: 14),

            // ── Additional prompt ─────────────────────────────────────────
            TextField(
              controller: _additionalPromptController,
              decoration: const InputDecoration(
                labelText: 'Additional instructions (optional)',
                hintText: 'e.g. Focus only on March transactions',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              maxLines: 2,
              enabled: !isExtracting,
            ),
            const SizedBox(height: 18),

            // ── Extract button ─────────────────────────────────────────────
            FilledButton.icon(
              onPressed: isExtracting || !isConfigured ? null : _startExtraction,
              icon: isExtracting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                isExtracting
                    ? 'Processing ${_provider.currentImageIndex} of ${_provider.totalImages}…'
                    : isConfigured
                        ? 'Extract Transactions'
                        : 'Set up API Key first',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],

          // ── Error message ─────────────────────────────────────────────────
          if (_provider.errorMessage != null) ...[
            const SizedBox(height: 14),
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _provider.errorMessage!,
                        style: TextStyle(color: Colors.red[700], fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // ── Info section (shown when no images selected) ───────────────────
          if (_provider.selectedImages.isEmpty) _InfoCard(theme: theme),
        ],
      ),
    );
  }
}

// ── API key status banner ─────────────────────────────────────────────────────

class _ApiKeyBanner extends StatelessWidget {
  final bool isConfigured;
  final VoidCallback onTap;

  const _ApiKeyBanner({required this.isConfigured, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isConfigured) {
      return Card(
        color: Colors.green.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: const Text(
            'Gemini API key configured',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: const Text('Tap to manage', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.key_off_outlined, color: theme.colorScheme.error, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gemini API key not set',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.error,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Tap to enter your free API key → get one at aistudio.google.com',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.error),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final ThemeData theme;
  const _InfoCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'How it works',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const _StepRow(step: '1', text: 'Enter your free Gemini API key (one-time)'),
            const _StepRow(step: '2', text: 'Add payment screenshots'),
            const _StepRow(step: '3', text: 'Tap "Extract" — Gemini reads the images'),
            const _StepRow(step: '4', text: 'Review & save transactions to Google Sheets'),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;
  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              step,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
