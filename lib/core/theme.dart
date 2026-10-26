import 'package:flutter/material.dart';

const green = Color(0xFF00AE87),
    blue = Color(0xFF365CFF),
    red = Color(0xFFFF233F);

/// Semantic surfaces and text colours shared by every screen and modal.
class AppColors {
  final bool dark;
  const AppColors(this.dark);
  Color get background =>
      dark ? const Color(0xFF292929) : const Color(0xFFFAFCFF);
  Color get surface => dark ? const Color(0xFF333333) : Colors.white;
  Color get field => dark ? const Color(0xFF303030) : const Color(0xFFFCFDFF);
  Color get ink => dark ? const Color(0xFFF3F5F8) : const Color(0xFF0B1638);
  Color get muted => dark ? const Color(0xFFBAC1CD) : const Color(0xFF75829C);
  Color get line => dark ? const Color(0xFF494949) : const Color(0xFFE8EDF5);
  Color get actionBlue => dark ? const Color(0xFF91A6FF) : blue;
  Color get tint => dark ? const Color(0xFF263C36) : const Color(0xFFEEFBF7);
  Color get noticeBackground =>
      dark ? const Color(0xFF443B25) : const Color(0xFFFFF6DF);
  Color get noticeForeground =>
      dark ? const Color(0xFFFFD889) : const Color(0xFF856020);
}

extension AppPalette on BuildContext {
  AppColors get appColors =>
      AppColors(Theme.of(this).brightness == Brightness.dark);
}

ThemeData appTheme({Brightness brightness = Brightness.light}) {
  final colors = AppColors(brightness == Brightness.dark);
  final base = ThemeData(useMaterial3: true, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: green,
      brightness: brightness,
      primary: green,
      secondary: blue,
      surface: colors.surface,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      outline: colors.line,
    ),
    textTheme: base.textTheme
        .apply(bodyColor: colors.ink, displayColor: colors.ink)
        .copyWith(
          headlineMedium: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: colors.ink,
          ),
          titleLarge: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.ink,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.ink,
          ),
          bodyMedium: TextStyle(fontSize: 14, color: colors.ink),
          bodySmall: TextStyle(fontSize: 12, color: colors.muted),
        ),
    iconTheme: IconThemeData(color: colors.ink),
    dividerColor: colors.line,
    appBarTheme: AppBarThemeData(
      backgroundColor: colors.background,
      foregroundColor: colors.ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.field,
      isDense: true,
      hintStyle: TextStyle(color: colors.muted),
      labelStyle: TextStyle(color: colors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: green, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: red, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
