import 'package:flutter/material.dart';

import '../models/gemma_model.dart';
import '../providers/gemma_provider.dart';
import '../widgets/model_card.dart';

class AiSetupScreen extends StatefulWidget {
  final bool isOnboarding;
  final VoidCallback? onDone;

  const AiSetupScreen({super.key, this.isOnboarding = false, this.onDone});

  @override
  State<AiSetupScreen> createState() => _AiSetupScreenState();
}

class _AiSetupScreenState extends State<AiSetupScreen> {
  final _provider = GemmaProvider.instance;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_rebuild);
    // init() is idempotent: first call fetches token + initializes;
    // subsequent calls just refresh install states (no Firebase call).
    _provider.init();
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _handleDone() {
    if (widget.onDone != null) {
      widget.onDone!();
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
            widget.isOnboarding ? 'Set up AI assistant' : 'Manage AI model'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: cs.surface,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // Description
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              widget.isOnboarding
                  ? 'Choose a model to download. It runs entirely on your '
                      'device — no data is sent to the cloud.'
                  : 'Download, switch, or remove on-device AI models.',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant, height: 1.5),
            ),
          ),

          // Checking-state shimmer
          if (_provider.isCheckingInstall) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],

          // Model cards — each card listens to the provider internally.
          // Download continues in the background if the user leaves this screen;
          // the card correctly reflects current state on return.
          for (final model in kGemmaCatalog) ...[
            GemmaModelCard(model: model),
            const SizedBox(height: 12),
          ],

          // AI-disabled banner
          if (_provider.aiDisabled) ...[
            const SizedBox(height: 4),
            _AiDisabledBanner(onEnable: () => _provider.setAiDisabled(false)),
          ],

          const SizedBox(height: 8),

          // Footer
          if (widget.isOnboarding)
            Center(
              child: TextButton(
                onPressed: _handleDone,
                child: const Text('Skip for now — continue to app'),
              ),
            )
          else if (_provider.isAnyInstalled)
            FilledButton(
              onPressed: _handleDone,
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}

class _AiDisabledBanner extends StatelessWidget {
  final VoidCallback onEnable;
  const _AiDisabledBanner({required this.onEnable});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI assistant is currently disabled. Re-enable it in Settings.',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onTertiaryContainer,
                  height: 1.4),
            ),
          ),
          TextButton(
            onPressed: onEnable,
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }
}

// Settings tile — "Disable AI assistant" toggle.
class AiDisableTile extends StatelessWidget {
  const AiDisableTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: GemmaProvider.instance,
      builder: (context, _) {
        final disabled = GemmaProvider.instance.aiDisabled;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Disable AI assistant'),
              subtitle: Text(
                disabled
                    ? 'AI is OFF. All AI buttons are hidden across the app.'
                    : 'Turn off if you don\'t want on-device AI features.',
                style: theme.textTheme.bodySmall,
              ),
              value: disabled,
              onChanged: (v) => GemmaProvider.instance.setAiDisabled(v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What disabling AI does',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    _bullet(theme,
                        'Frees up ~1–2 GB of RAM immediately — model unloads right away.'),
                    _bullet(theme, 'Hides every AI button, tip, and chat screen.'),
                    _bullet(theme,
                        'Downloaded model files stay on your device. Re-enable anytime without re-downloading.'),
                    const SizedBox(height: 6),
                    Text(
                      'Want to reclaim storage too? Delete the model above.',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bullet(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  '),
          Expanded(
            child:
                Text(text, style: theme.textTheme.bodySmall?.copyWith(height: 1.4)),
          ),
        ]),
      );
}
