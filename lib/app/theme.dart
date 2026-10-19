import 'package:flutter/material.dart';

/// Centralized theme configuration for LearnX.
///
/// Exposes light and dark [ThemeData] built from a single seed color so the
/// app has a consistent Material 3 look across mobile, web, and desktop.
class AppTheme {
  const AppTheme._();

  /// Brand seed color used to derive the Material 3 color schemes.
  static const Color seedColor = Color(0xFF3B6EF5);

  /// Light theme used by the app shell.
  static ThemeData get light => _build(Brightness.light);

  /// Dark theme used by the app shell.
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
    );
  }
}
