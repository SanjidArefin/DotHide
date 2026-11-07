import 'package:flutter/material.dart';

/// Simple grey/white monochrome palette. No saturated accent colours anywhere.
abstract final class Grey {
  static const Color black = Color(0xFF111111);
  static const Color ink = Color(0xFF212121);
  static const Color charcoal = Color(0xFF424242);
  static const Color slate = Color(0xFF616161);
  static const Color muted = Color(0xFF757575);
  static const Color hint = Color(0xFF9E9E9E);
  static const Color line = Color(0xFFE0E0E0);
  static const Color fill = Color(0xFFF0F0F0);
  static const Color mist = Color(0xFFF7F7F7);
  static const Color white = Color(0xFFFFFFFF);
}

abstract final class AppTheme {
  static ThemeData light() => _build(_lightScheme, Brightness.light);

  static ThemeData dark() => _build(_darkScheme, Brightness.dark);

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Grey.charcoal,
    onPrimary: Grey.white,
    primaryContainer: Grey.fill,
    onPrimaryContainer: Grey.ink,
    secondary: Grey.slate,
    onSecondary: Grey.white,
    secondaryContainer: Grey.fill,
    onSecondaryContainer: Grey.ink,
    tertiary: Grey.muted,
    onTertiary: Grey.white,
    error: Color(0xFF8D3B3B),
    onError: Grey.white,
    surface: Grey.white,
    onSurface: Grey.ink,
    surfaceContainerLowest: Grey.white,
    surfaceContainerLow: Grey.mist,
    surfaceContainer: Grey.mist,
    surfaceContainerHigh: Grey.fill,
    surfaceContainerHighest: Grey.line,
    onSurfaceVariant: Grey.muted,
    outline: Grey.hint,
    outlineVariant: Grey.line,
    shadow: Color(0x1A000000),
    scrim: Color(0x80000000),
    inverseSurface: Grey.ink,
    onInverseSurface: Grey.white,
    inversePrimary: Grey.line,
  );

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Grey.line,
    onPrimary: Grey.black,
    primaryContainer: Grey.charcoal,
    onPrimaryContainer: Grey.white,
    secondary: Grey.hint,
    onSecondary: Grey.black,
    secondaryContainer: Grey.charcoal,
    onSecondaryContainer: Grey.white,
    tertiary: Grey.muted,
    onTertiary: Grey.black,
    error: Color(0xFFB98A8A),
    onError: Grey.black,
    surface: Color(0xFF171717),
    onSurface: Grey.fill,
    surfaceContainerLowest: Color(0xFF0D0D0D),
    surfaceContainerLow: Color(0xFF1C1C1C),
    surfaceContainer: Color(0xFF212121),
    surfaceContainerHigh: Color(0xFF2A2A2A),
    surfaceContainerHighest: Color(0xFF333333),
    onSurfaceVariant: Grey.hint,
    outline: Grey.slate,
    outlineVariant: Color(0xFF3A3A3A),
    shadow: Color(0x33000000),
    scrim: Color(0x99000000),
    inverseSurface: Grey.fill,
    onInverseSurface: Grey.black,
    inversePrimary: Grey.charcoal,
  );

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.onSurfaceVariant),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(0, 44),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.onSurface),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.surface : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.onSurface : scheme.surfaceContainerHighest,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color),
      );
}
