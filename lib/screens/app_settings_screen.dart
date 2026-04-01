import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:MoneyTracker/services/theme_preference_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour presets
// ─────────────────────────────────────────────────────────────────────────────

/// Preset swatches for the "shared" context (greens, teals, cyans).
const List<_ColorPreset> _sharedPresets = [
  _ColorPreset(Color(0xFF1B5E20), 'Forest'),
  _ColorPreset(Color(0xFF2E7D32), 'Green'),
  _ColorPreset(Color(0xFF388E3C), 'Leaf'),
  _ColorPreset(Color(0xFF00695C), 'Teal'),
  _ColorPreset(Color(0xFF00838F), 'Cyan'),
  _ColorPreset(Color(0xFF006064), 'Dark Cyan'),
  _ColorPreset(Color(0xFF558B2F), 'Olive'),
  _ColorPreset(Color(0xFF33691E), 'Moss'),
];

/// Preset swatches for the "personal" context (blues, indigos, purples).
const List<_ColorPreset> _personalPresets = [
  _ColorPreset(Color(0xFF0D47A1), 'Navy'),
  _ColorPreset(Color(0xFF1565C0), 'Blue'),
  _ColorPreset(Color(0xFF1976D2), 'Sky Blue'),
  _ColorPreset(Color(0xFF283593), 'Indigo'),
  _ColorPreset(Color(0xFF311B92), 'Deep Purple'),
  _ColorPreset(Color(0xFF4527A0), 'Purple'),
  _ColorPreset(Color(0xFF1A237E), 'Midnight'),
  _ColorPreset(Color(0xFF006064), 'Peacock'),
];

class _ColorPreset {
  const _ColorPreset(this.color, this.label);
  final Color color;
  final String label;
}

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

/// App-wide settings: theme mode + accent colours for shared / personal sheets.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  // ── Theme mode tile ────────────────────────────────────────────────────────
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

  // ── Section header ─────────────────────────────────────────────────────────
  Widget _sectionHeader(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ── Colour section (presets + custom picker) ───────────────────────────────
  Widget _colorSection({
    required BuildContext context,
    required String label,
    required Color current,
    required List<_ColorPreset> presets,
    required void Function(Color) onChanged,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current colour chip + label
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: current,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: current.withValues(alpha: 0.45),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Preset swatches
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in presets)
                _SwatchChip(
                  color: p.color,
                  label: p.label,
                  selected: current == p.color,
                  onTap: () => onChanged(p.color),
                ),
              // "Custom" picker tile
              _CustomPickerChip(
                current: current,
                isCustom: !presets.any((p) => p.color == current),
                onPick: (c) => onChanged(c),
              ),
            ],
          ),
        ],
      ),
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
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ── Theme mode ─────────────────────────────────────────────────
              _sectionHeader(
                context,
                'Appearance',
                'Choose light, dark, or follow your device setting.',
              ),
              _themeOptionTile(
                context: context,
                svc: svc,
                value: ThemeMode.system,
                title: 'System default',
                subtitle: 'Follow your device light / dark mode',
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

              const Divider(height: 32, indent: 16, endIndent: 16),

              // ── Accent colours ─────────────────────────────────────────────
              _sectionHeader(
                context,
                'Accent colours',
                'Shared sheets use the first colour; personal sheets use the second.',
              ),

              // Shared colour
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Shared sheet colour',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              _colorSection(
                context: context,
                label: 'Current: shared',
                current: svc.sharedColor,
                presets: _sharedPresets,
                onChanged: svc.setSharedColor,
              ),

              const SizedBox(height: 20),

              // Personal colour
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  'Personal sheet colour',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              _colorSection(
                context: context,
                label: 'Current: personal',
                current: svc.personalColor,
                presets: _personalPresets,
                onChanged: svc.setPersonalColor,
              ),

              // Live preview strip
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ColorPreviewStrip(
                  sharedColor: svc.sharedColor,
                  personalColor: svc.personalColor,
                ),
              ),

              // Reset button
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () {
                    svc.setSharedColor(
                      ThemePreferenceService.defaultSharedColor,
                    );
                    svc.setPersonalColor(
                      ThemePreferenceService.defaultPersonalColor,
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset to defaults'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Swatch chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _SwatchChip extends StatelessWidget {
  const _SwatchChip({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: selected ? 2.5 : 0,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? 0.7 : 0.35),
                blurRadius: selected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom picker chip
// ─────────────────────────────────────────────────────────────────────────────

class _CustomPickerChip extends StatefulWidget {
  const _CustomPickerChip({
    required this.current,
    required this.isCustom,
    required this.onPick,
  });

  final Color current;
  final bool isCustom;
  final void Function(Color) onPick;

  @override
  State<_CustomPickerChip> createState() => _CustomPickerChipState();
}

class _CustomPickerChipState extends State<_CustomPickerChip> {
  late Color _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.current;
  }

  @override
  void didUpdateWidget(_CustomPickerChip old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _draft = widget.current;
  }

  Future<void> _openPicker() async {
    _draft = widget.current;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a custom colour'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (ctx2, setDs) => ColorPicker(
              pickerColor: _draft,
              onColorChanged: (c) {
                setDs(() => _draft = c);
              },
              enableAlpha: false,
              labelTypes: const [ColorLabelType.hex, ColorLabelType.rgb],
              pickerAreaHeightPercent: 0.7,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onPick(_draft);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Custom colour',
      child: GestureDetector(
        onTap: _openPicker,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isCustom ? widget.current : Colors.transparent,
            border: Border.all(
              color: widget.isCustom
                  ? Colors.white
                  : theme.colorScheme.outline.withValues(alpha: 0.6),
              width: widget.isCustom ? 2.5 : 1.5,
            ),
            boxShadow: widget.isCustom
                ? [
                    BoxShadow(
                      color: widget.current.withValues(alpha: 0.6),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Icon(
            Icons.colorize,
            size: 18,
            color: widget.isCustom
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live preview strip
// ─────────────────────────────────────────────────────────────────────────────

class _ColorPreviewStrip extends StatelessWidget {
  const _ColorPreviewStrip({
    required this.sharedColor,
    required this.personalColor,
  });

  final Color sharedColor;
  final Color personalColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preview',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PreviewCard(
                color: sharedColor,
                label: 'Shared sheet',
                icon: Icons.groups_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PreviewCard(
                color: personalColor,
                label: 'Personal sheet',
                icon: Icons.person_outline,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: onColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: onColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
