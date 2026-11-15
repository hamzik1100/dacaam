import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing, radius and elevation scale.
///
/// Everything in the app snaps to this scale so cards, gutters and gaps stay
/// visually consistent across the six primary screens.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Horizontal page gutter used by every screen body.
  static const double gutter = 16;

  /// Height reserved for the custom bottom navigation bar.
  static const double bottomNavHeight = 64;

  /// Minimum tappable size for restaurant staff working quickly.
  static const double touchTarget = 48;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius cardLarge = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(24),
  );
}

class AppShadows {
  const AppShadows._();

  /// Soft ambient shadow for white cards. Deliberately low-contrast — the
  /// hierarchy comes from spacing, not heavy drop shadows.
  static List<BoxShadow> card(BuildContext context) => <BoxShadow>[
    BoxShadow(
      color: context.palette.shadow,
      blurRadius: 18,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> raised(BuildContext context) => <BoxShadow>[
    BoxShadow(
      color: context.palette.shadow,
      blurRadius: 28,
      spreadRadius: -8,
      offset: const Offset(0, 14),
    ),
  ];

  /// Coloured glow used under the primary CTA only.
  static List<BoxShadow> brand() => <BoxShadow>[
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.32),
      blurRadius: 20,
      spreadRadius: -4,
      offset: const Offset(0, 10),
    ),
  ];
}

/// Animation timings. Kept short — staff must never wait for the UI.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 140);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration chart = Duration(milliseconds: 620);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasis = Curves.easeOutBack;
}
