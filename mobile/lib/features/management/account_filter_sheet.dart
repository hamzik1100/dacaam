import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/finance.dart';
import '../../redux/states/finance_state.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Narrows the money list: which account, what kind of movement, when.
///
/// Nothing is selected by default. "Where is the money" is the question this
/// screen exists to answer, and a date window applied before being asked would
/// hide an account that last moved a fortnight ago.
Future<AccountFilters?> showAccountFilterSheet(
  BuildContext context,
  AccountFilters current,
  List<Account> accounts,
) {
  return showAppSheet<AccountFilters>(
    context,
    builder: (BuildContext context) =>
        _FilterSheet(current: current, accounts: accounts),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.accounts});

  final AccountFilters current;
  final List<Account> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late AccountFilters _draft = widget.current;

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: context.t('filters'),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GradientButton(
            label: context.t('apply'),
            height: 50,
            onPressed: () => Navigator.of(context).pop(_draft),
          ),
          if (!_draft.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const AccountFilters()),
              child: Text(context.t('clearFilters')),
            ),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Group(
            title: context.t('account'),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: widget.accounts.map((Account a) {
                final bool on = _draft.accountId == a.id;

                return ChoiceChip(
                  label: Text(a.name),
                  selected: on,
                  onSelected: (_) => setState(
                    () => _draft = on
                        ? _draft.copyWith(clearAccount: true)
                        : _draft.copyWith(accountId: a.id),
                  ),
                );
              }).toList(),
            ),
          ),

          _Group(
            title: context.t('transactionKind'),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: TransactionKind.values.map((TransactionKind k) {
                final bool on = _draft.kind == k;

                return ChoiceChip(
                  label: Text(context.t(k.labelKey)),
                  selected: on,
                  onSelected: (_) => setState(
                    () => _draft = on
                        ? _draft.copyWith(clearKind: true)
                        : _draft.copyWith(kind: k),
                  ),
                );
              }).toList(),
            ),
          ),

          _Group(
            title: context.t('date'),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children:
                  <ReportRange>[
                    ReportRange.today,
                    ReportRange.sevenDays,
                    ReportRange.thirtyDays,
                    ReportRange.thisMonth,
                    ReportRange.lastMonth,
                  ].map((ReportRange r) {
                    final bool on = _draft.range == r;

                    return ChoiceChip(
                      label: Text(context.t(r.labelKey)),
                      selected: on,
                      onSelected: (_) => setState(
                        () => _draft = on
                            ? _draft.copyWith(clearRange: true)
                            : _draft.copyWith(range: r),
                      ),
                    );
                  }).toList(),
            ),
          ),

          _Group(
            title: context.t('search'),
            child: TextFormField(
              initialValue: _draft.search,
              decoration: InputDecoration(
                hintText: context.t('searchDescription'),
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
              ),
              onChanged: (String v) =>
                  _draft = _draft.copyWith(search: v.trim()),
            ),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: context.texts.titleSmall?.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
