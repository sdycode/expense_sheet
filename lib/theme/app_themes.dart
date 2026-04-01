import 'package:flutter/material.dart';
import '../services/theme_preference_service.dart';

/// Light and dark [ThemeData]. The seed color is taken from
/// [ThemePreferenceService.sharedColor] (the app-wide primary accent) so
/// users can personalise it while only brightness/contrast change per mode.
class AppThemes {
  AppThemes._();

  static ThemeData light({Color? seedColor}) {
    final seed = seedColor ??
        ThemePreferenceService.defaultSharedColor;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }

  static ThemeData dark({Color? seedColor}) {
    final seed = seedColor ??
        ThemePreferenceService.defaultSharedColor;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
