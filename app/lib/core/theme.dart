import 'package:flutter/material.dart';

/// Dark TV-friendly theme: high contrast, large touch/focus targets.
abstract final class AppTheme {
  /// Selectable accent seeds for the in-app theme switcher (OSD menu).
  static const seeds = <Color>[
    Color(0xFF7C4DFF), // violet (default)
    Color(0xFF2196F3), // blue
    Color(0xFF009688), // teal
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // amber
    Color(0xFFE91E63), // pink
  ];

  static const names = ['Violet', 'Blue', 'Teal', 'Green', 'Amber', 'Pink'];

  static ThemeData dark({Color? seed}) {
    seed ??= seeds.first;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF121212),
      focusColor: base.colorScheme.primary,
      cardTheme: const CardThemeData(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
