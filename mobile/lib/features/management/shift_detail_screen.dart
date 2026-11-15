import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/shift.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';

/// One closed shift, in full.
///
/// The history row shows a single number, and a variance on its own is close to
/// meaningless: twenty thousand short is a catastrophe on a quiet Monday and a
/// rounding slip on a day that took four million. This is the page that lets
/// somebody judge it — who was there, what each account held, what actually
/// moved through the till, and what was spent out of it.
class ShiftDetailScreen extends StatefulWidget {
  const ShiftDetailScreen({super.key, required this.shiftId});

  final int shiftId;

  @override
  State<ShiftDetailScreen> createState() => _ShiftDetailScreenState();
}

class _ShiftDetailScreenState extends State<ShiftDetailScreen> {
  ShiftDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ShiftDetail detail = await Effects.shiftDetail(
        StoreProvider.of<AppState>(context, listen: false),
        widget.shiftId,
      );

      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ShiftDetail? d = _detail;

    return Scaffold(
      appBar: AppBar(title: Text(context.t('shiftDetail'))),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            )
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.gutter),
              children: <Widget>[
                _Summary(detail: d),
                const SizedBox(height: AppSpacing.lg),
                if (d.accounts.isNotEmpty) ...<Widget>[
                  _Accounts(lines: d.accounts),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (d.expenses.items.isNotEmpty) ...<Widget>[
                  _Expenses(expenses: d.expenses),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (d.movements.isNotEmpty) _Movements(movements: d.movements),
              ],
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.detail});

  final ShiftDetail detail;

  @override
  Widget build(BuildContext context) {
    final Shift s = detail.shift;
    final double variance = s.variance ?? 0;
    final Color tone = s.balanced
        ? AppColors.success
        : (variance < 0 ? AppColors.danger : AppColors.secondary);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  s.isOpen
                      ? context.t('tillOpen')
                      : context.t(
                          s.balanced ? 'tillBalanced' : 'tillDoesNotBalance',
                        ),
                  style: context.texts.titleMedium?.copyWith(
                    color: s.isOpen ? null : tone,
                  ),
                ),
              ),
              StatusChip(
                label: context.t(s.isOpen ? 'open' : 'closed'),
                color: s.isOpen ? AppColors.success : AppColors.secondary,
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),

          _Line(label: context.t('openedBy'), value: s.openedBy),
          _Line(
            label: context.t('openedAt'),
            value: Fmt.dateTime(s.openedAt, context.lang),
          ),
          _Line(
            label: context.t('openingFloat'),
            value: Fmt.money(s.openingFloat),
          ),

          if (s.overnightDiff != null && s.overnightDiff!.abs() > 0.01)
            _Line(
              label: context.t('overnightDiff'),
              value: Fmt.money(s.overnightDiff!),
              color: AppColors.danger,
            ),

          if (!s.isOpen) ...<Widget>[
            const Divider(height: AppSpacing.lg),
            _Line(label: context.t('closedBy'), value: s.closedBy),
            if (s.closedAt != null)
              _Line(
                label: context.t('closedAt'),
                value: Fmt.dateTime(s.closedAt!, context.lang),
              ),
            const Divider(height: AppSpacing.lg),
            _Line(
              label: context.t('expected'),
              value: Fmt.money(s.expectedClose ?? 0),
            ),
            _Line(
              label: context.t('counted'),
              value: Fmt.money(s.countedClose ?? 0),
            ),
            _Line(
              label: context.t('difference'),
              value: Fmt.money(variance),
              color: tone,
              bold: true,
            ),

            if ((s.closeReason ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.palette.muted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t('reason'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.palette.subtext,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(s.closeReason!),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// The breakdown. A single total would net a short drawer against an over one
/// and report a clean night, which is what this exists to prevent.
class _Accounts extends StatelessWidget {
  const _Accounts({required this.lines});

  final List<ShiftCount> lines;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t('byAccount'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),

          for (final ShiftCount c in lines) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        Fmt.money(c.variance),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: c.balanced
                              ? AppColors.success
                              : (c.isShort
                                    ? AppColors.danger
                                    : AppColors.secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${context.t('expected')} ${Fmt.money(c.expected)}  ·  '
                    '${context.t('counted')} ${Fmt.money(c.counted)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
            ),
            if (c != lines.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _Expenses extends StatelessWidget {
  const _Expenses({required this.expenses});

  final ShiftExpenses expenses;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t('expensesToday'),
                  style: context.texts.titleMedium,
                ),
              ),
              Text(
                Fmt.money(expenses.total),
                style: context.texts.titleSmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final ShiftExpenseLine e in expenses.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.palette.subtext),
                    ),
                  ),
                  Text(Fmt.money(e.amount)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Everything that moved through the till while it was open.
///
/// This is where a variance stops being a mystery: a short drawer next to a
/// refund nobody remembers, or a transfer out at eleven at night, explains
/// itself the moment the two are on the same page.
class _Movements extends StatelessWidget {
  const _Movements({required this.movements});

  final List<ShiftMovement> movements;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.t('movements'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final ShiftMovement m in movements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          m.description.isEmpty ? m.kind : m.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          Fmt.time(m.at),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.subtext,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Fmt.money(m.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: m.isOut ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: TextStyle(color: context.palette.subtext)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                fontSize: bold ? 17 : 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
