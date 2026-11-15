import 'package:flutter/material.dart';

/// Brand palette for the DACAAM restaurant POS.
///
/// The identity is orange/amber on near-white surfaces. Gradients are reserved
/// for a small set of "hero" surfaces (primary CTA, checkout, featured cards)
/// so the product keeps reading as a professional SaaS tool rather than a
/// colourful template.
class AppColors {
  const AppColors._();

  // ---- Brand -------------------------------------------------------------
  static const Color primary = Color(0xFFF97316); // Deep Orange
  static const Color secondary = Color(0xFFF59E0B); // Amber
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);

  // Supporting accents, used only inside charts and category tints.
  static const Color info = Color(0xFF3B82F6);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color teal = Color(0xFF14B8A6);
  static const Color pink = Color(0xFFEC4899);

  // ---- Light surfaces ----------------------------------------------------
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color textLight = Color(0xFF0F172A);
  static const Color subtextLight = Color(0xFF64748B);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color mutedLight = Color(0xFFF1F5F9);

  // ---- Dark surfaces -----------------------------------------------------
  static const Color bgDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color textDark = Color(0xFFF8FAFC);
  static const Color subtextDark = Color(0xFF94A3B8);
  static const Color borderDark = Color(0xFF334155);
  static const Color mutedDark = Color(0xFF263449);

  // ---- Gradients ---------------------------------------------------------
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[primary, secondary],
  );

  /// Softer variant used behind large hero cards so text stays readable.
  static const LinearGradient brandSoft = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[Color(0xFFF97316), Color(0xFFFB923C), Color(0xFFF59E0B)],
  );

  /// Palette used to colour category / chart series consistently everywhere.
  static const List<Color> series = <Color>[
    primary,
    secondary,
    info,
    violet,
    success,
    teal,
    pink,
    danger,
  ];
}

/// Surface colours resolved for the active brightness.
///
/// Exposed as a [ThemeExtension] so widgets never branch on
/// `Theme.of(context).brightness` by hand.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.muted,
    required this.text,
    required this.subtext,
    required this.border,
    required this.shadow,
    required this.overlay,
  });

  final Color background;
  final Color card;
  final Color muted;
  final Color text;
  final Color subtext;
  final Color border;
  final Color shadow;
  final Color overlay;

  static const AppPalette light = AppPalette(
    background: AppColors.bgLight,
    card: AppColors.cardLight,
    muted: AppColors.mutedLight,
    text: AppColors.textLight,
    subtext: AppColors.subtextLight,
    border: AppColors.borderLight,
    shadow: Color(0x140F172A),
    overlay: Color(0x660F172A),
  );

  static const AppPalette dark = AppPalette(
    background: AppColors.bgDark,
    card: AppColors.cardDark,
    muted: AppColors.mutedDark,
    text: AppColors.textDark,
    subtext: AppColors.subtextDark,
    border: AppColors.borderDark,
    shadow: Color(0x40000000),
    overlay: Color(0x99000000),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? card,
    Color? muted,
    Color? text,
    Color? subtext,
    Color? border,
    Color? shadow,
    Color? overlay,
  }) {
    return AppPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      muted: muted ?? this.muted,
      text: text ?? this.text,
      subtext: subtext ?? this.subtext,
      border: border ?? this.border,
      shadow: shadow ?? this.shadow,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      text: Color.lerp(text, other.text, t)!,
      subtext: Color.lerp(subtext, other.subtext, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  TextTheme get texts => Theme.of(this).textTheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
