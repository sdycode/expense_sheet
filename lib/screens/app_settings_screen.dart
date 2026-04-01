import 'package:flutter/material.dart';
import 'package:MoneyTracker/services/theme_preference_service.dart';

/// App-wide settings (appearance). Theme uses the same primary seed (blue) in
/// light and dark; surfaces and text follow the selection.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  Widget _themeOptionTile({
    required BuildContext context,
    required ThemePreferenceService svc,
    required ThemeMode value,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final selected = svc.themeMode == value;
    return ListTile(
      leading: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: () => svc.setThemeMode(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final svc = ThemePreferenceService.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('App settings')),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Appearance',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Primary accent stays blue; text, icons, and surfaces '
                  'adapt to light or dark.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _themeOptionTile(
                context: context,
                svc: svc,
                value: ThemeMode.system,
                title: 'System default',
                subtitle: 'Use your device light or dark mode',
              ),
              _themeOptionTile(
                context: context,
                svc: svc,
                value: ThemeMode.light,
                title: 'Light',
              ),
              _themeOptionTile(
                context: context,
                svc: svc,
                value: ThemeMode.dark,
                title: 'Dark',
              ),
            ],
          );
        },
      ),
    );
  }
}
