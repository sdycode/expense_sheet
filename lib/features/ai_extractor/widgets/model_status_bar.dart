import 'package:flutter/material.dart';

/// Compact status bar showing whether the AI model files are configured.
///
/// Green = both model paths set; red/amber = not configured.
/// Tapping opens the model setup screen.
class ModelStatusBar extends StatelessWidget {
  final bool isConfigured;
  final bool isLoaded;
  final VoidCallback onTap;

  const ModelStatusBar({
    super.key,
    required this.isConfigured,
    required this.isLoaded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bgColor;
    final Color fgColor;
    final IconData icon;
    final String label;

    if (isLoaded) {
      bgColor = Colors.green.withValues(alpha: 0.12);
      fgColor = Colors.green;
      icon = Icons.check_circle;
      label = 'Model ready';
    } else if (isConfigured) {
      bgColor = Colors.orange.withValues(alpha: 0.12);
      fgColor = Colors.orange;
      icon = Icons.memory;
      label = 'Model configured · Tap to load';
    } else {
      bgColor = Colors.red.withValues(alpha: 0.12);
      fgColor = Colors.red;
      icon = Icons.warning_amber_rounded;
      label = 'Model not set up · Tap to configure';
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: fgColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: fgColor, size: 20),
          ],
        ),
      ),
    );
  }
}
