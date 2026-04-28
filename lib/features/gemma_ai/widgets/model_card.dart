import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/gemma_model.dart';
import '../providers/gemma_provider.dart';
import '../services/gemma_service.dart';

enum _CardState { notInstalled, installedNotActive, active }

// Pure display card — all values passed in, no provider coupling.
class ModelCard extends StatelessWidget {
  final GemmaModel model;
  final bool isInstalled;
  final bool isActive;
  final bool isDownloading;
  final double downloadProgress; // 0.0–1.0
  final String? errorMessage;
  final GemmaAuthException? authException;
  final VoidCallback onDownload;
  final VoidCallback onActivate;
  final VoidCallback onRetry;
  final VoidCallback? onDelete;

  const ModelCard({
    super.key,
    required this.model,
    required this.isInstalled,
    required this.isActive,
    required this.isDownloading,
    required this.downloadProgress,
    this.errorMessage,
    this.authException,
    required this.onDownload,
    required this.onActivate,
    required this.onRetry,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final state = isActive
        ? _CardState.active
        : isInstalled
            ? _CardState.installedNotActive
            : _CardState.notInstalled;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        // surfaceContainerLow is visually distinct from the scaffold's surface
        // in both light and dark themes, making card boundaries clear.
        color: cs.surfaceContainerLow,
        border: Border.all(
          color: state == _CardState.active ? cs.primary : cs.outlineVariant,
          width: state == _CardState.active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + size + badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.sizeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(state: state),
              ],
            ),

            const SizedBox(height: 6),
            Text(
              model.tagline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),

            // Progress bar (visible during download)
            if (isDownloading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: downloadProgress > 0 ? downloadProgress : null,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.download_rounded, size: 14, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    downloadProgress > 0
                        ? 'Downloading… ${(downloadProgress * 100).toStringAsFixed(0)}%'
                        : 'Starting download…',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            // Error blocks
            if (!isDownloading) ...[
              if (authException != null) ...[
                const SizedBox(height: 12),
                _AuthErrorBlock(authException: authException!, onRetry: onRetry),
              ] else if (errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBlock(message: errorMessage!, onRetry: onRetry),
              ],
            ],

            // Action row (hidden while downloading)
            if (!isDownloading) ...[
              const SizedBox(height: 14),
              _ActionRow(
                state: state,
                model: model,
                onDownload: onDownload,
                onActivate: onActivate,
                onDelete: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _CardState state;
  const _StatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == _CardState.notInstalled) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final isActive = state == _CardState.active;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? cs.primary : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'ACTIVE' : 'INSTALLED',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isActive ? cs.onPrimary : cs.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final _CardState state;
  final GemmaModel model;
  final VoidCallback onDownload;
  final VoidCallback onActivate;
  final VoidCallback? onDelete;

  const _ActionRow({
    required this.state,
    required this.model,
    required this.onDownload,
    required this.onActivate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (state) {
      _CardState.notInstalled => SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Download (${model.sizeLabel})'),
          ),
        ),
      _CardState.installedNotActive => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onActivate,
                child: const Text('Use this model'),
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete model files',
                onPressed: onDelete,
                color: cs.error,
              ),
            ],
          ],
        ),
      _CardState.active => Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Currently in use',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete model files',
                onPressed: onDelete,
                color: cs.error,
              ),
          ],
        ),
    };
  }
}

class _ErrorBlock extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBlock({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12, color: cs.onErrorContainer, height: 1.4)),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                foregroundColor: cs.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _AuthErrorBlock extends StatelessWidget {
  final GemmaAuthException authException;
  final VoidCallback onRetry;
  const _AuthErrorBlock({required this.authException, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: cs.onErrorContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'License acceptance required',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Open the model page on HuggingFace, sign in, tap "Agree and access", then come back and retry.',
            style:
                TextStyle(fontSize: 12, color: cs.onErrorContainer, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(authException.acceptLicenseUrl);
                    if (await canLaunchUrl(url)) launchUrl(url);
                    await Clipboard.setData(
                        ClipboardData(text: authException.acceptLicenseUrl));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied')));
                    }
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cs.onErrorContainer,
                      side: BorderSide(color: cs.onErrorContainer.withAlpha(80)),
                      textStyle: const TextStyle(fontSize: 12)),
                  icon: const Icon(Icons.open_in_browser, size: 14),
                  label: const Text('Open model page'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                    foregroundColor: cs.onErrorContainer,
                    textStyle: const TextStyle(fontSize: 12)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Self-contained reactive card ───────────────────────────────────────────
//
// Listens to GemmaProvider.instance internally — no local install state.
// Download continues even when the user navigates away; the card correctly
// reflects the current state when they return because it reads from the
// singleton provider on every rebuild.
class GemmaModelCard extends StatelessWidget {
  final GemmaModel model;
  const GemmaModelCard({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GemmaProvider.instance,
      builder: (context, _) {
        final p = GemmaProvider.instance;
        final isInstalled = p.isInstalledFor(model.id);
        final isActive = p.selectedModel.id == model.id && isInstalled;
        final isThisDownloading =
            p.isDownloading && p.downloadingModel?.id == model.id;

        // Error state persists in _lastErrorModel after _downloadingModel is cleared.
        final isThisErrored = p.lastErrorModel?.id == model.id;
        final authErr = isThisErrored ? p.authException : null;
        final errMsg = (isThisErrored && authErr == null) ? p.downloadError : null;

        return ModelCard(
          model: model,
          isInstalled: isInstalled,
          isActive: isActive,
          isDownloading: isThisDownloading,
          downloadProgress: isThisDownloading ? p.downloadProgress : 0,
          authException: authErr,
          errorMessage: errMsg,
          onDownload: () => p.installModel(model),
          onActivate: () {
            p.selectModel(model);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${model.name} is now active.')),
            );
          },
          onRetry: () => p.installModel(model),
          onDelete: isInstalled
              ? () => p.deleteModel(model)
              : null,
        );
      },
    );
  }
}
