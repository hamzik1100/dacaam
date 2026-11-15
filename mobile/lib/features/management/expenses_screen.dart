import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/finance.dart';
import '../../data/repository/dacaam_repository.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import 'expense_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/states.dart';

/// Daily and monthly spend. Monthly entries carry a recurring flag so rent and
/// salaries aren't re-entered every month.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ExpensesVm>(
      converter: _ExpensesVm.from,
      builder: (BuildContext context, _ExpensesVm vm) {
        final List<Expense> visible = vm.visible;

        // Cancelled entries stay on the list but leave the total, matching what
        // the server counts. Summing them here would put a different figure on
        // this screen than the one the reports show, and two screens disagreeing
        // about spend is a bug nobody can diagnose from the outside.
        final double total = visible
            .where((Expense e) => !e.isCancelled)
            .fold<double>(0, (double s, Expense e) => s + e.amount);

        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('expenses')),
            actions: <Widget>[
              if (vm.canCreate)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.gutter),
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => showExpenseSheet(
                        context,
                        categories: vm.categories,
                        onSave: vm.onSave,
                      ),
                      child: const SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.lg,
                ),
                child: Column(
                  children: <Widget>[
                    SegmentedTabs(
                      labels: <String>[
                        context.t('today'),
                        context.t('thisMonth'),
                      ],
                      index: vm.kind == ExpenseKind.daily ? 0 : 1,
                      onChanged: (int i) => vm.onKind(
                        i == 0 ? ExpenseKind.daily : ExpenseKind.monthly,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppCard(
                      child: Row(
                        children: <Widget>[
                          const IconBadge(
                            icon: Icons.account_balance_wallet_rounded,
                            color: AppColors.violet,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  context.t('totalExpenses'),
                                  style: context.texts.labelMedium,
                                ),
                                Text(
                                  Fmt.money(total),
                                  style: context.texts.titleLarge,
                                ),
                              ],
                            ),
                          ),
                          StatusChip(
                            label: '${visible.length}',
                            color: AppColors.violet,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_rounded,
                        title: context.t('noExpenses'),
                        actionLabel: vm.canCreate
                            ? context.t('addExpense2')
                            : null,
                        onAction: vm.canCreate
                            ? () => showExpenseSheet(
                                context,
                                categories: vm.categories,
                                onSave: vm.onSave,
                              )
                            : null,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          0,
                          AppSpacing.gutter,
                          AppSpacing.xxl,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (BuildContext context, int i) {
                          return Entrance(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: _ExpenseTile(
                                expense: visible[i],
                                category: vm.categoryOf(visible[i].categoryId),
                                onTap: vm.canEdit
                                    ? () => showExpenseSheet(
                                        context,
                                        expense: visible[i],
                                        categories: vm.categories,
                                        onSave: vm.onSave,
                                        onCancel: vm.canCancel
                                            ? vm.onCancel
                                            : null,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.category,
    this.onTap,
  });

  final Expense expense;
  final ExpenseCategory? category;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = category?.color ?? AppColors.violet;
    final bool voided = expense.isCancelled;

    return Opacity(
      // Dimmed and struck through rather than removed. A cancelled entry
      // that looks like a live one makes the totals unexplainable; one
      // that disappears recreates the problem cancelling was meant to fix.
      opacity: voided ? 0.55 : 1,
      child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          IconBadge(
            icon: category?.icon ?? Icons.receipt_rounded,
            color: color,
            size: 42,
            iconSize: 20,
            radius: 12,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        expense.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleMedium?.copyWith(
                          decoration: voided
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (expense.recurring) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        Icons.autorenew_rounded,
                        size: 13,
                        color: context.palette.subtext,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  voided && expense.cancelReason.isNotEmpty
                      ? '${context.t('expenseCancelled')} · ${expense.cancelReason}'
                      : '${expense.categoryName} · ${Fmt.date(expense.date, context.lang)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodySmall?.copyWith(
                    color: voided ? AppColors.danger : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                Fmt.money(expense.amount),
                style: context.texts.titleSmall?.copyWith(
                  color: AppColors.danger,
                  decoration: voided ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(
                label: expense.method.label,
                color: expense.method.color,
                dense: true,
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

class _ExpensesVm {
  const _ExpensesVm({
    required this.visible,
    required this.categories,
    required this.kind,
    required this.canCreate,
    required this.canEdit,
    required this.canCancel,
    required this.onKind,
    required this.onSave,
    required this.onCancel,
    required this.categoryOf,
  });

  factory _ExpensesVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _ExpensesVm(
      visible: s.expenses.visible,
      categories: s.expenses.categories,
      kind: s.expenses.kind,
      canCreate: s.auth.can(Permission.expensesCreate),
      canEdit: s.auth.can(Permission.expensesEdit),
      canCancel: s.auth.can(Permission.expensesDelete),
      onKind: (ExpenseKind k) => store.dispatch(ExpenseKindChanged(k)),
      onSave: (ExpenseRequest r) => Effects.saveExpense(store, r),
      onCancel: (int id, String reason) =>
          Effects.cancelExpense(store, id, reason),
      categoryOf: (int id) {
        for (final ExpenseCategory c in s.expenses.categories) {
          if (c.id == id) return c;
        }

        return null;
      },
    );
  }

  final List<Expense> visible;
  final List<ExpenseCategory> categories;
  final ExpenseKind kind;
  final bool canCreate;
  final bool canEdit;
  final bool canCancel;
  final ValueChanged<ExpenseKind> onKind;
  final Future<void> Function(ExpenseRequest) onSave;
  final Future<void> Function(int, String) onCancel;
  final ExpenseCategory? Function(int) categoryOf;
}
