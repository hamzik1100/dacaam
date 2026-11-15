import 'package:flutter/material.dart';

/// Typography scale.
///
/// We intentionally ride on the platform UI font (Roboto / SF) instead of a
/// downloaded webfont: the app must render identically on a cheap Android
/// handset with no network in the middle of service. Hierarchy is carried by
/// weight and tracking rather than by exotic families.
class AppTypography {
  const AppTypography._();

  static TextTheme build(Color text, Color subtext) {
    return TextTheme(
      // Big KPI numbers and success screens.
      displaySmall: TextStyle(
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: text,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: text,
      ),
      // Screen titles.
      headlineSmall: TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: text,
      ),
      // Section headers, card headlines.
      titleLarge: TextStyle(
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: text,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: text,
      ),
      titleSmall: TextStyle(
        fontSize: 13.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: text,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: text),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.45, color: subtext),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: subtext),
      labelLarge: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: text,
      ),
      labelMedium: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: subtext,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: subtext,
      ),
    );
  }
}
