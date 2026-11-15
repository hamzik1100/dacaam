import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/settings_state.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/common.dart';

/// Fires a save without awaiting it, and says why if it fails.
///
/// The effect has already put the old value back by the time this runs, so the
/// switch springs back on its own. That alone looks like the control simply
/// ignored the tap, which is the confusing half of the bug this replaces — the
/// message is what tells the user the server refused.
void _save(BuildContext context, Future<void> Function() run) {
  unawaited(
    run().catchError((Object e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : '$e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }),
  );
}

/// General settings.
///
/// Everything here changes app behaviour immediately — tax and the packaging
/// fee re-price the live cart, language re-renders every string — and each
/// change is persisted as it is made, so there is no save step to forget.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _SettingsVm>(
      converter: _SettingsVm.from,
      builder: (BuildContext context, _SettingsVm vm) {
        final SettingsState s = vm.settings;
        final bool editable = vm.canManage;

        return Scaffold(
          appBar: AppBar(title: Text(context.t('settings'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: <Widget>[
              _Section(
                title: context.t('profile'),
                children: <Widget>[
                  DetailRow(
                    label: context.t('name'),
                    value: vm.restaurantName,
                    icon: Icons.storefront_rounded,
                  ),
                  DetailRow(
                    label: 'Restaurant Code',
                    value: vm.slug,
                    icon: Icons.qr_code_rounded,
                  ),
                  DetailRow(
                    label: context.t('phone'),
                    value: vm.phone,
                    icon: Icons.phone_rounded,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              _Section(
                title: context.t('language'),
                children: <Widget>[
                  _ChoiceRow<AppLanguage>(
                    values: AppLanguage.values,
                    selected: s.language,
                    labelOf: (AppLanguage l) => l == AppLanguage.somali
                        ? context.t('somali')
                        : context.t('english'),
                    onSelected: (AppLanguage l) =>
                        _save(context, () => vm.onLanguage(l)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              _Section(
                title: context.t('appearance'),
                children: <Widget>[
                  _ChoiceRow<ThemeMode>(
                    values: const <ThemeMode>[
                      ThemeMode.light,
                      ThemeMode.dark,
                      ThemeMode.system,
                    ],
                    selected: s.themeMode,
                    labelOf: (ThemeMode m) => switch (m) {
                      ThemeMode.light => context.t('light'),
                      ThemeMode.dark => context.t('dark'),
                      ThemeMode.system => context.t('systemDefault'),
                    },
                    onSelected: vm.onThemeMode,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              _Section(
                title: '${context.t('tax')} & ${context.t('packagingFee')}',
                children: <Widget>[
                  SwitchListTile.adaptive(
                    value: s.taxEnabled,
                    onChanged: editable
                        ? (bool v) => _save(
                            context,
                            () => vm.onToggle(SettingToggled(taxEnabled: v)),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t('tax'),
                      style: context.texts.titleSmall,
                    ),
                    subtitle: Text(
                      '${Fmt.decimal(s.taxRate)}%',
                      style: context.texts.bodySmall,
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                  _Divider(),
                  _NumberRow(
                    label: context.t('tax'),
                    value: s.taxRate,
                    suffix: '%',
                    enabled: editable,
                    onChanged: (double v) => _save(
                      context,
                      () => vm.onValue(SettingValueChanged(taxRate: v)),
                    ),
                  ),
                  _Divider(),
                  SwitchListTile.adaptive(
                    value: s.packagingFeeEnabled,
                    onChanged: editable
                        ? (bool v) => _save(
                            context,
                            () => vm.onToggle(
                              SettingToggled(packagingFeeEnabled: v),
                            ),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t('packagingFee'),
                      style: context.texts.titleSmall,
                    ),
                    subtitle: Text(
                      Fmt.money(s.packagingFee),
                      style: context.texts.bodySmall,
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                  _Divider(),
                  _NumberRow(
                    label: context.t('amount'),
                    value: s.packagingFee,
                    prefix: s.currencyPrefix,
                    enabled: editable,
                    onChanged: (double v) => _save(
                      context,
                      () => vm.onValue(SettingValueChanged(packagingFee: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              _Section(
                title: context.t('orderType'),
                children: <Widget>[
                  SwitchListTile.adaptive(
                    value: s.requireTableForDineIn,
                    onChanged: editable
                        ? (bool v) => _save(
                            context,
                            () => vm.onToggle(
                              SettingToggled(requireTableForDineIn: v),
                            ),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Require Table for Dine In',
                      style: context.texts.titleSmall,
                    ),
                    subtitle: Text(
                      context.t('tableRequired'),
                      style: context.texts.bodySmall,
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                  _Divider(),
                  SwitchListTile.adaptive(
                    value: s.guestCountEnabled,
                    onChanged: editable
                        ? (bool v) => _save(
                            context,
                            () => vm.onToggle(
                              SettingToggled(guestCountEnabled: v),
                            ),
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.t('guests'),
                      style: context.texts.titleSmall,
                    ),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.lg),

              // Not a restaurant setting, so it is not gated on
              // settings.manage and never reaches the server: the same account
              // runs on the counter tablet and on a manager's phone, and only
              // one of those is worth locking.
              _Section(
                title: context.t('security'),
                children: const <Widget>[_BiometricToggle()],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Face / fingerprint over the stored session, stored on this handset only.
class _BiometricToggle extends StatefulWidget {
  const _BiometricToggle();

  @override
  State<_BiometricToggle> createState() => _BiometricToggleState();
}

class _BiometricToggleState extends State<_BiometricToggle> {
  bool _enabled = false;
  bool _available = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bool available = await Effects.lock.isAvailable();
    final bool enabled = await Effects.lock.isEnabled();

    if (mounted) {
      setState(() {
        _available = available;
        _enabled = enabled && available;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 48);

    return SwitchListTile.adaptive(
      value: _enabled,
      // Off and unchangeable on a handset with no sensor or no enrolment.
      // Offering the switch there would let somebody turn on a lock that can
      // never open.
      onChanged: _available
          ? (bool v) async {
              // Prove the sensor works before trusting the app to it. Turning
              // this on and finding out at the next launch that the prompt
              // fails would lock the till.
              if (v && !await Effects.lock.authenticate()) return;

              await Effects.lock.setEnabled(v);
              if (mounted) setState(() => _enabled = v);
            }
          : null,
      contentPadding: EdgeInsets.zero,
      title: Text(context.t('biometricLock'), style: context.texts.titleSmall),
      subtitle: Text(
        _available
            ? context.t('biometricLockHelp')
            : context.t('biometricUnavailable'),
        style: context.texts.bodySmall,
      ),
      secondary: Icon(
        Icons.fingerprint_rounded,
        color: _available ? AppColors.primary : context.palette.subtext,
      ),
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.primary,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            title.toUpperCase(),
            style: context.texts.labelSmall?.copyWith(letterSpacing: 1),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: context.palette.border);
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: values.map((T v) {
          final bool isSelected = v == selected;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Material(
                color: isSelected ? AppColors.primary : context.palette.muted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(v),
                  child: Container(
                    height: 40,
                    alignment: Alignment.center,
                    child: Text(
                      labelOf(v),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        color: isSelected
                            ? Colors.white
                            : context.palette.subtext,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Tap-to-edit numeric row backed by a small prompt sheet.
class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.prefix,
    this.suffix,
  });

  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _edit(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: context.texts.titleSmall)),
            Text(
              '${prefix == null ? '' : '$prefix '}${Fmt.decimal(value)}${suffix ?? ''}',
              style: context.texts.titleSmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.edit_rounded, size: 15, color: context.palette.subtext),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Not toStringAsFixed(0): opening a 2.5% rate on a box that reads "2" and
    // saving turns it into 2 without the user ever touching the digits.
    final TextEditingController controller = TextEditingController(
      text: Fmt.editable(value),
    );
    final double? result = await showAppSheet<double>(
      context,
      builder: (BuildContext context) => AppSheet(
        title: label,
        footer: FilledButton(
          onPressed: () => Navigator.pop(
            context,
            double.tryParse(controller.text.replaceAll(',', '')),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          child: Text(context.t('save')),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          // Plain TextInputType.number gives Android a keypad with no decimal
          // point, so a 2.5% rate is physically untypeable.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: prefix == null ? null : '$prefix  ',
            suffixText: suffix,
          ),
        ),
      ),
    );
    controller.dispose();
    if (result != null && result >= 0) onChanged(result);
  }
}

class _SettingsVm {
  const _SettingsVm({
    required this.settings,
    required this.restaurantName,
    required this.slug,
    required this.phone,
    required this.canManage,
    required this.onLanguage,
    required this.onThemeMode,
    required this.onToggle,
    required this.onValue,
  });

  factory _SettingsVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _SettingsVm(
      settings: s.settings,
      restaurantName: s.restaurant.restaurant?.name ?? '',
      slug: s.restaurant.restaurant?.slug ?? '',
      phone: s.restaurant.restaurant?.phone ?? '',
      canManage: s.auth.can(Permission.settingsManage),
      // Each of these persists. Dispatching alone was the bug: the change
      // lived in memory, bootstrap reloaded the server's row on the next
      // launch, and every setting appeared to reset itself.
      onLanguage: (AppLanguage l) => Effects.saveSettings(
        store,
        store.state.settings.copyWith(language: l),
      ),
      onToggle: (SettingToggled a) => Effects.saveSettings(
        store,
        store.state.settings.copyWith(
          taxEnabled: a.taxEnabled,
          packagingFeeEnabled: a.packagingFeeEnabled,
          requireTableForDineIn: a.requireTableForDineIn,
          guestCountEnabled: a.guestCountEnabled,
        ),
      ),
      onValue: (SettingValueChanged a) => Effects.saveSettings(
        store,
        store.state.settings.copyWith(
          taxRate: a.taxRate,
          packagingFee: a.packagingFee,
          currencyPrefix: a.currencyPrefix,
        ),
      ),
      // Appearance is a property of the device, not the restaurant: the same
      // account runs on a bright counter tablet and a dim phone.
      onThemeMode: (ThemeMode m) => store.dispatch(ThemeModeChanged(m)),
    );
  }

  final SettingsState settings;
  final String restaurantName;
  final String slug;
  final String phone;
  final bool canManage;
  final Future<void> Function(AppLanguage) onLanguage;
  final ValueChanged<ThemeMode> onThemeMode;
  final Future<void> Function(SettingToggled) onToggle;
  final Future<void> Function(SettingValueChanged) onValue;
}
