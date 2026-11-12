import 'package:flutter/material.dart';

/// Hệ thống màu sắc & kiểu dáng chuẩn từ bản thiết kế Google Stitch
/// (`stitch_ai_document_scanner_app/ai_document_scanner_vietnamese_ocr/DESIGN.md`).
class StitchTheme {
  StitchTheme._();

  // Light Mode Surfaces & Backgrounds
  static const Color surface = Color(0xFFF8F9FD);
  static const Color surfaceLight = Color(0xFFF8FAFB);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F3F8);
  static const Color surfaceContainer = Color(0xFFECEEF2);
  static const Color surfaceContainerHigh = Color(0xFFE7E8EC);
  static const Color surfaceContainerHighest = Color(0xFFE1E2E7);
  static const Color surfaceNeutralPill = Color(0xFFF1F5F9);

  // Studio Pro Dark Surfaces (Camera & Page Editor)
  static const Color surfaceProBase = Color(0xFF101316);
  static const Color surfaceProEditor = Color(0xFF14171A);
  static const Color surfaceProElevated = Color(0xFF1C2126);
  static const Color surfaceDarkControls = Color(0xFF0F1215);

  // Brand Primary & AI Accents
  static const Color primary = Color(0xFF004F45);
  static const Color primaryContainer = Color(0xFF00695C);
  static const Color primaryContainerLight = Color(0xFFE0F2F1);
  static const Color primaryContainerDark = Color(0xFF004D40);
  static const Color primaryDarkAccent = Color(0xFF26A69A);
  static const Color primaryFixed = Color(0xFFA0F2E1);
  static const Color primaryFixedDim = Color(0xFF84D5C5);

  // Secondary / Dynamic AI Mesh Cyan
  static const Color secondary = Color(0xFF006875);
  static const Color secondaryContainer = Color(0xFF00E3FD);
  static const Color secondaryFixed = Color(0xFF9CF0FF);
  static const Color secondaryFixedDim = Color(0xFF00DAF3);

  // Tertiary / Shutter Intelligence Mint
  static const Color tertiary = Color(0xFF004F40);
  static const Color tertiaryContainer = Color(0xFF006956);
  static const Color tertiaryFixed = Color(0xFF5FFBD6);
  static const Color tertiaryFixedDim = Color(0xFF38DEBB);

  // Text & Borders
  static const Color onSurface = Color(0xFF191C1F);
  static const Color onSurfaceVariant = Color(0xFF3E4946);
  static const Color textMain = Color(0xFF191C1F);
  static const Color textSubtle = Color(0xFF3E4946);
  static const Color textDarkMuted = Color(0xFF9CA3AF);
  static const Color outline = Color(0xFF6E7976);
  static const Color outlineVariant = Color(0xFFBEC9C5);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderDark = Color(0xFF2D3748);

  // Semantic Status Colors
  static const Color statusSuccess = Color(0xFF10B981);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color surfaceWarningLight = Color(0xFFFFFBEB);
  static const Color statusDangerStamp = Color(0xFFEF4444);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  static ThemeData buildLightTheme() {
    const colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: Color(0xFF94E5D5),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: Color(0xFF00616D),
      tertiary: tertiary,
      onTertiary: Colors.white,
      tertiaryContainer: tertiaryContainer,
      error: error,
      onError: Colors.white,
      errorContainer: errorContainer,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'BeVietnamPro',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surfaceWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderLight, width: 1),
        ),
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  static ThemeData buildDarkTheme() {
    const colorScheme = ColorScheme.dark(
      primary: primaryDarkAccent,
      onPrimary: Colors.white,
      primaryContainer: primaryContainerDark,
      onPrimaryContainer: primaryFixed,
      secondary: secondaryFixedDim,
      onSecondary: Color(0xFF001F24),
      secondaryContainer: secondary,
      tertiary: tertiaryFixed,
      error: statusDangerStamp,
      surface: surfaceProEditor,
      onSurface: Colors.white,
      onSurfaceVariant: outlineVariant,
      outline: borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'BeVietnamPro',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceProEditor,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceProElevated,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      visualDensity: VisualDensity.standard,
    );
  }
}
