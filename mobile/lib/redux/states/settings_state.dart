import 'package:flutter/material.dart';

import '../../core/utils/enums.dart';

/// Restaurant-level configuration that changes how orders are priced and how
/// the app is presented. Backed by `restaurant_settings` from Phase 2 on.
@immutable
class SettingsState {
  const SettingsState({
    this.language = AppLanguage.somali,
    this.themeMode = ThemeMode.light,
    this.currencyPrefix = 'SLSH',
    this.taxRate = 5,
    this.taxEnabled = false,
    this.packagingFeeEnabled = true,
    this.packagingFee = 5000,
    this.requireTableForDineIn = true,
    this.guestCountEnabled = true,
  });

  /// Somali is the product default.
  final AppLanguage language;

  /// Light is the default; Dark and System are opt-in.
  final ThemeMode themeMode;

  final String currencyPrefix;

  /// Percent, e.g. `5` == 5%.
  final double taxRate;

  /// Seeded OFF so demo totals match the published price list exactly
  /// (a 35,000 burger rings up as 35,000). Flip it in Settings to price with
  /// tax; every total in the app recomputes from this flag.
  final bool taxEnabled;

  final bool packagingFeeEnabled;

  /// Flat fee applied once per takeaway order.
  final double packagingFee;

  final bool requireTableForDineIn;
  final bool guestCountEnabled;

  double get taxFraction => taxEnabled ? taxRate / 100 : 0;

  SettingsState copyWith({
    AppLanguage? language,
    ThemeMode? themeMode,
    String? currencyPrefix,
    double? taxRate,
    bool? taxEnabled,
    bool? packagingFeeEnabled,
    double? packagingFee,
    bool? requireTableForDineIn,
    bool? guestCountEnabled,
  }) {
    return SettingsState(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      currencyPrefix: currencyPrefix ?? this.currencyPrefix,
      taxRate: taxRate ?? this.taxRate,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      packagingFeeEnabled: packagingFeeEnabled ?? this.packagingFeeEnabled,
      packagingFee: packagingFee ?? this.packagingFee,
      requireTableForDineIn:
          requireTableForDineIn ?? this.requireTableForDineIn,
      guestCountEnabled: guestCountEnabled ?? this.guestCountEnabled,
    );
  }
}
