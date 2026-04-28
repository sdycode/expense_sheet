import 'package:flutter/material.dart';

import '../models/gemma_model.dart';
import '../providers/gemma_provider.dart';
import '../screens/ai_setup_screen.dart';

// Drop-in error widget for any AI surface. Shows friendly copy + retry/upgrade CTAs.
class AiErrorWidget extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? heading;
  final String? detail;

  const AiErrorWidget({super.key, this.onRetry, this.heading, this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selected = GemmaProvider.instance.selectedModel;
    final canUpgrade = selected.id != kGemmaCatalog.last.id;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              heading ?? 'Our AI is still learning',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              detail ??
                  'Couldn\'t finish that request. Retry, or pick a larger '
                      'on-device model in AI Settings for better answers.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (onRetry != null)
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            if (canUpgrade) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AiSetupScreen())),
                child: const Text('Upgrade model →'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Async-value error placeholder for Isar / stream failures (not AI).
Widget buildAsyncErrorPlaceholder(
  Object error,
  StackTrace? stack, {
  String? where,
  String? message,
}) {
  debugPrint('[${where ?? 'Async'}] $error\n$stack');
  return Builder(builder: (context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 32, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            message ??
                "Couldn't load this right now. Pull to refresh or try again in a moment.",
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(height: 1.5),
          ),
        ]),
      ),
    );
  });
}
