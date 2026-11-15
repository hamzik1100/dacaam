import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/shift.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/actions.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/states.dart';
import 'shift_detail_screen.dart';

/// Opening and counting the till.
///
/// The screen is built around one rule: whoever is counting must not be able to
/// see what the system expects. It is not shown while the shift is open, it is
/// not shown on the counting sheet, and it appears exactly once — after the
/// count has been submitted — so the person can see how they did.
///
/// Given the number in advance, anyone would type the number. A variance that
/// is always zero is worse than no count, because it looks like a control.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  @override
  void initState() {
    super.initState();

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );

    // Put away any reveal left over from a previous close. It carries the
    // expected total, and the next person to open this screen is the next
    // person about to count — which is exactly who should not see one.
    store.dispatch(const ShiftRevealDismissed());

    Effects.loadShift(store);

    if (store.state.auth.can(Permission.shiftsView)) {
      Effects.loadShiftHistory(store);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ShiftVm>(
      converter: _ShiftVm.from,
      builder: (BuildContext context, _ShiftVm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('shift'))),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            children: <Widget>[
              if (vm.justClosed != null) ...<Widget>[
                _Reveal(shift: vm.justClosed!, onDismiss: vm.onDismissReveal),
                const SizedBox(height: AppSpacing.lg),
              ],

              _TillCard(vm: vm),

              if (vm.canView) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Text(context.t('shiftHistory'), style: context.texts.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (vm.history.isEmpty)
                  EmptyState(
                    icon: Icons.point_of_sale_rounded,
                    title: context.t('noShifts'),
                  )
                else
                  ...vm.history.map(
                    (Shift s) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _HistoryTile(
                        shift: s,
                        // Only a closed shift opens. An open one has no
                        // figures to show, and a detail page that filled
                        // in the expected total for a till still being
                        // counted would hand over the one number the
                        // whole feature keeps back.
                        onTap: s.isOpen
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ShiftDetailScreen(shiftId: s.id),
                                ),
                              ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The till, open or closed.
class _TillCard extends StatelessWidget {
  const _TillCard({required this.vm});

  final _ShiftVm vm;

  @override
  Widget build(BuildContext context) {
    final Shift? open = vm.open;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t(open == null ? 'tillClosed' : 'tillOpen'),
                  style: context.texts.titleLarge,
                ),
              ),
              StatusChip(
                label: context.t(open == null ? 'closed' : 'open'),
                color: open == null ? AppColors.danger : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          if (open == null) ...<Widget>[
            // What the last shift counted is not shown here. Whoever is about
            // to count the drawer would read it and enter it, and the morning
            // gap would close itself on paper. It appears afterwards, as the
            // overnight difference, which is where it means something.
            Text(
              // A waiter cannot open a till, so telling them to count the
              // drawer is an instruction they cannot act on.
              context.t(vm.canManage ? 'openTillNote' : 'askManagerToOpen'),
              style: TextStyle(color: context.palette.subtext),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (vm.canManage)
              GradientButton(
                label: context.t('openTill'),
                icon: Icons.lock_open_rounded,
                onPressed: () => _open(context, vm),
              ),
          ] else ...<Widget>[
            _Row(label: context.t('openedBy'), value: open.openedBy),
            _Row(
              label: context.t('openedAt'),
              value: Fmt.time(open.openedAt),
            ),
            _Row(
              label: context.t('openingFloat'),
              value: Fmt.money(open.openingFloat),
            ),

            if (open.overnightDiff != null && open.overnightDiff!.abs() > 0.01)
              _Row(
                label: context.t('overnightDiff'),
                value: Fmt.money(open.overnightDiff!),
                color: AppColors.danger,
              ),

            const SizedBox(height: AppSpacing.md),

            // Says out loud that the figure is being withheld, so it reads as
            // deliberate rather than as something the screen failed to load.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: context.palette.muted,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.visibility_off_rounded,
                    size: 18,
                    color: context.palette.subtext,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      context.t('countNote'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.palette.subtext,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            if (vm.canManage)
              GradientButton(
                label: context.t('countAndClose'),
                icon: Icons.calculate_rounded,
                onPressed: () => _close(context, vm, open),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, _ShiftVm vm) async {
    // No `initial`, deliberately.
    //
    // It used to arrive pre-filled with what the previous shift counted, which
    // meant opening the till was one tap on a number somebody else had written.
    // The overnight difference then came out as exactly zero every morning —
    // and money taken between a close and the next open, which is the one thing
    // that figure exists to catch, became invisible.
    final double? amount = await _askAmount(
      context,
      title: context.t('openTill'),
      note: context.t('openTillPrompt'),
    );

    if (amount == null || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await vm.onOpen(amount);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _close(BuildContext context, _ShiftVm vm, Shift open) async {
    // Every account, each starting from an empty field. A pre-filled number is
    // a number that gets accepted, and the whole point is that the figure comes
    // from the drawer rather than from the screen.
    final Map<int, double>? counts = await showDialog<Map<int, double>>(
      context: context,
      builder: (BuildContext context) => _CountSheet(
        accounts: vm.accounts,
        expenses: vm.expenses,
      ),
    );

    if (counts == null || !context.mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await vm.onClose(open.id, counts, '');
    } on ApiException catch (e) {
      if (!context.mounted) return;

      // The server refuses a large difference without an explanation. Ask for
      // one and send the same counts again — never different ones.
      if (e.fields.containsKey('reason')) {
        final String? reason = await _askReason(context, e.fields['reason']!);

        if (reason == null || !context.mounted) return;

        try {
          await vm.onClose(open.id, counts, reason);
        } on ApiException catch (e2) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(e2.message),
              backgroundColor: AppColors.danger,
            ),
          );
        }

        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }
  Future<double?> _askAmount(
    BuildContext context, {
    required String title,
    required String note,
  }) async {
    final TextEditingController controller = TextEditingController();

    // StatefulBuilder so a rejected entry can say why. Without it the Confirm
    // button simply returned and the dialog sat there, which reads as the app
    // having frozen rather than as the number being wrong.
    final double? out = await showDialog<double>(
      context: context,
      builder: (BuildContext context) {
        String? error;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.subtext,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixText: '${Fmt.prefix}  ',
                    labelText: context.t('amount'),
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.t('goBack')),
              ),
              FilledButton(
                onPressed: () {
                  // Commas stripped first. Money is shown as 200,000 all through
                  // this app, so that is what people type — and tryParse answers
                  // null to it.
                  final double? value = double.tryParse(
                    controller.text.replaceAll(',', '').trim(),
                  );

                  if (value == null || value < 0) {
                    setLocal(() => error = context.t('enterAValidAmount'));

                    return;
                  }

                  Navigator.pop(context, value);
                },
                child: Text(context.t('confirm')),
              ),
            ],
          ),
        );
      },
    );

    controller.dispose();

    return out;
  }

  Future<String?> _askReason(BuildContext context, String message) async {
    final TextEditingController controller = TextEditingController();

    final String? out = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('reason')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: context.t('reasonHint')),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.t('goBack')),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length < 3) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );

    controller.dispose();

    return out;
  }
}

/// The one moment the expected total is meant to be on screen.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.shift, required this.onDismiss});

  final Shift shift;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final double variance = shift.variance ?? 0;
    final bool balanced = shift.balanced;
    final Color color = balanced
        ? AppColors.success
        : (variance < 0 ? AppColors.danger : AppColors.secondary);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                balanced ? Icons.check_circle_rounded : Icons.error_rounded,
                color: color,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.t(balanced ? 'tillBalanced' : 'tillDoesNotBalance'),
                  style: context.texts.titleMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _Row(
            label: context.t('expected'),
            value: Fmt.money(shift.expectedClose ?? 0),
          ),
          _Row(
            label: context.t('counted'),
            value: Fmt.money(shift.countedClose ?? 0),
          ),
          const Divider(height: AppSpacing.lg),
          _Row(
            label: context.t('difference'),
            value: Fmt.money(variance),
            color: color,
            bold: true,
          ),

          if (shift.ordersOutside > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              '${context.t('ordersOutsideShift')}: ${shift.ordersOutside}',
              style: const TextStyle(fontSize: 12, color: AppColors.secondary),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: onDismiss,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            child: Text(context.t('done')),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.shift, this.onTap});

  final Shift shift;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double variance = shift.variance ?? 0;
    final bool balanced = shift.balanced;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  shift.closedBy.isEmpty ? shift.openedBy : shift.closedBy,
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.dateTime(shift.closedAt ?? shift.openedAt, context.lang),
                  style: context.texts.bodySmall,
                ),
                if ((shift.closeReason ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    shift.closeReason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                shift.isOpen ? '—' : Fmt.money(variance),
                style: context.texts.titleSmall?.copyWith(
                  color: shift.isOpen
                      ? context.palette.subtext
                      : (balanced
                            ? AppColors.success
                            : (variance < 0
                                  ? AppColors.danger
                                  : AppColors.secondary)),
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(
                label: context.t(shift.isOpen ? 'open' : 'closed'),
                color: shift.isOpen ? AppColors.success : AppColors.secondary,
                dense: true,
              ),
            ],
          ),
          if (onTap != null) ...<Widget>[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.palette.subtext,
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
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
          // Flexible: a long label beside a seven-figure sum overflows on a
          // narrow phone, and more so at a large system font size.
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

class _ShiftVm {
  const _ShiftVm({
    required this.open,
    required this.lastClose,
    required this.accounts,
    required this.expenses,
    required this.history,
    required this.justClosed,
    required this.canManage,
    required this.canView,
    required this.onOpen,
    required this.onClose,
    required this.onDismissReveal,
  });

  final Shift? open;
  final double? lastClose;
  final List<CountableAccount> accounts;
  final ShiftExpenses expenses;
  final List<Shift> history;
  final Shift? justClosed;
  final bool canManage;
  final bool canView;
  final Future<void> Function(double) onOpen;
  final Future<void> Function(int, Map<int, double>, String) onClose;
  final VoidCallback onDismissReveal;

  factory _ShiftVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _ShiftVm(
      open: s.shifts.open,
      lastClose: s.shifts.lastClose,
      accounts: s.shifts.till?.accounts ?? const <CountableAccount>[],
      expenses: s.shifts.till?.expenses ?? const ShiftExpenses(),
      history: s.shifts.history,
      justClosed: s.shifts.lastClosed,
      canManage: s.auth.can(Permission.shiftsManage),
      canView: s.auth.can(Permission.shiftsView),
      onOpen: (double amount) => Effects.openShift(store, amount),
      onClose: (int id, Map<int, double> counts, String reason) =>
          Effects.closeShift(store, id, counts, reason: reason),
      onDismissReveal: () => store.dispatch(const ShiftRevealDismissed()),
    );
  }
}

/// Counting the drawers.
///
/// One field per account, all empty, with nothing on screen that hints at what
/// any of them should say. The day's expenses are shown because they are why
/// the cash drawer holds less than the day's sales — the cashier paid them, so
/// it is not news, but without it a close turns into a panicked recount of
/// money that was legitimately spent.
class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.accounts, required this.expenses});

  final List<CountableAccount> accounts;
  final ShiftExpenses expenses;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  late final Map<int, TextEditingController> _fields = <int, TextEditingController>{
    for (final CountableAccount a in widget.accounts) a.id: TextEditingController(),
  };

  String? _error;

  @override
  void dispose() {
    for (final TextEditingController c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.t('countAndClose')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.t('countPrompt'),
              style: TextStyle(fontSize: 13, color: context.palette.subtext),
            ),
            const SizedBox(height: AppSpacing.lg),

            // No accounts came back, which in practice means the server is
            // older than this build and does not send the list yet.
            // Rendering an empty form would give somebody a Confirm button
            // that submits nothing and answers with a validation error they
            // cannot act on; saying what is wrong is the honest failure.
            if (widget.accounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  context.t('noAccountsToCount'),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),

            for (final CountableAccount a in widget.accounts) ...<Widget>[
              TextField(
                controller: _fields[a.id],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: a.name,
                  prefixText: '${Fmt.prefix}  ',
                  // Both sides of the account: what came in, and what went back
                  // out of it. A drawer that is short has to be looked into
                  // before the shift closes, and these are what it is checked
                  // against — a missed expense, a payment rung up wrong.
                  //
                  // The closing total is still not among them. The figure in
                  // the box is theirs to write.
                  helperText: _helperFor(context, a),
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (widget.expenses.items.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
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
                      '${context.t('expensesToday')} — ${Fmt.money(widget.expenses.total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final ShiftExpenseLine e in widget.expenses.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.palette.subtext,
                                ),
                              ),
                            ),
                            Text(
                              Fmt.money(e.amount),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.subtext,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t('goBack')),
        ),
        FilledButton(
          onPressed: widget.accounts.isEmpty ? null : _submit,
          child: Text(context.t('confirm')),
        ),
      ],
    );
  }

  /// What the box says underneath itself.
  ///
  /// Cash gets the instruction as well as the figures, because counting a
  /// drawer is a different act from reading a balance off a phone.
  String _helperFor(BuildContext context, CountableAccount a) {
    final List<String> parts = <String>[];

    if (a.received != null) {
      parts.add('${context.t('receivedThisShift')} ${Fmt.money(a.received!)}');
    }

    if (a.paidOut > 0.01) {
      parts.add('${context.t('paidOutThisShift')} ${Fmt.money(a.paidOut)}');
    }

    parts.add(
      a.isCash ? context.t('countTheDrawer') : context.t('enterAppBalance'),
    );

    return parts.join('  ·  ');
  }

  void _submit() {
    final Map<int, double> counts = <int, double>{};

    for (final CountableAccount a in widget.accounts) {
      // Same comma handling as everywhere else that takes money.
      final double? value = double.tryParse(
        _fields[a.id]!.text.replaceAll(',', '').trim(),
      );

      // Every account or none. Skipping one would report a balanced till while
      // a hole sat in the account nobody was asked about — the server refuses
      // it too, but saying so here avoids a round trip to be told off.
      if (value == null || value < 0) {
        setState(() => _error = '${context.t('countEveryAccount')}: ${a.name}');

        return;
      }

      counts[a.id] = value;
    }

    Navigator.pop(context, counts);
  }
}