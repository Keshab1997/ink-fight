import 'package:flutter/material.dart';

abstract final class InkColors {
  static const ink = Color(0xFF101010);
  static const inkSoft = Color(0xFF282828);
  static const paper = Color(0xFFF7F7F2);
  static const paperDeep = Color(0xFFECECE5);
  static const line = Color(0xFFD5D5CE);
  static const muted = Color(0xFF73736E);
  static const white = Color(0xFFFFFFFF);
}

abstract final class InkFightTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: InkColors.ink,
      brightness: Brightness.light,
      surface: InkColors.paper,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: InkColors.ink,
        onPrimary: InkColors.white,
        surface: InkColors.paper,
        onSurface: InkColors.ink,
      ),
      scaffoldBackgroundColor: InkColors.paper,
      fontFamily: 'sans-serif',
      splashFactory: InkRipple.splashFactory,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: InkColors.ink,
        contentTextStyle: TextStyle(
          color: InkColors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: InkColors.paper,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: InkColors.ink,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: TextStyle(
          color: InkColors.inkSoft,
          fontSize: 15,
          height: 1.45,
        ),
      ),
    );
  }
}
