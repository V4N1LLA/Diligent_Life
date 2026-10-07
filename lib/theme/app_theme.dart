import 'package:flutter/material.dart';

abstract final class AppSpace {
  static const tiny = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 20.0;
  static const page = 24.0;
  static const section = 32.0;
}

abstract final class AppStyle {
  static const accent = Color(0xFF547565);
  static const radius = 20.0;
  static const controlRadius = 16.0;
  static const iconSize = 24.0;
  static const touchTarget = 48.0;
  static const reward = Color(0xFF75609A);
  static const panelRadius = 28.0;
}

ThemeData appTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppStyle.accent,
        brightness: brightness,
      ).copyWith(
        tertiary: brightness == Brightness.light
            ? AppStyle.reward
            : const Color(0xFFD6B9F5),
        onTertiary: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF38264F),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: -1.5,
      ),
      headlineMedium: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w500,
        height: 1.35,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5),
      bodySmall: TextStyle(fontSize: 12, height: 1.5),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppStyle.panelRadius),
        ),
      ),
    ),
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppStyle.radius),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 8,
      borderRadius: BorderRadius.circular(AppStyle.radius),
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: AppSpace.medium),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppStyle.touchTarget),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyle.controlRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppStyle.touchTarget, AppStyle.touchTarget),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppStyle.radius)),
      ),
      contentPadding: EdgeInsets.all(16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyle.radius),
        ),
      ),
    ),
  );
}
