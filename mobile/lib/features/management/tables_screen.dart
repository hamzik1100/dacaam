import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/dining_table.dart';
import '../../data/models/order.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../orders/order_details_sheet.dart';

/// Floor view. Colour carries the status so a manager can read the room at a
/// glance; occupied tables surface their live order.
class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _TablesVm>(
      converter: _TablesVm.from,
      builder: (BuildContext context, _TablesVm vm) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.t('tables')),
            actions: <Widget>[
              if (vm.canManage)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.gutter),
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _editTable(context, vm, null),
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
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            children: <Widget>[
              Row(
                children: TableStatus.values.map((TableStatus s) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _StatusCount(status: s, count: vm.countOf(s)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.xl),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.92,
                ),
                itemCount: vm.tables.length,
                itemBuilder: (BuildContext context, int i) {
                  final DiningTable t = vm.tables[i];
                  return Entrance(
                    index: i,
                    stagger: const Duration(milliseconds: 30),
                    child: _TableCard(
                      table: t,
                      order: vm.orderFor(t),
                      onTap: () {
                        final RestaurantOrder? order = vm.orderFor(t);
                        // An occupied table's order is what staff want first;
                        // its settings are an admin concern.
                        if (order != null) {
                          showOrderDetailsSheet(context, order.id);
                        } else if (vm.canManage) {
                          _editTable(context, vm, t);
                        }
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editTable(
    BuildContext context,
    _TablesVm vm,
    DiningTable? table,
  ) async {
    await showAppSheet<void>(
      context,
      builder: (BuildContext sheetContext) => _TableSheet(
        table: table,
        onSave: vm.onSave,
        onDelete: table == null ? null : () => vm.onDelete(table.id),
      ),
    );
  }
}

/// Create or edit a table. Deleting is really deactivating — past orders point
/// at this row, and a floor plan that loses its history is not a floor plan.
class _TableSheet extends StatefulWidget {
  const _TableSheet({this.table, required this.onSave, this.onDelete});

  final DiningTable? table;
  final Future<void> Function(DiningTable) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<_TableSheet> createState() => _TableSheetState();
}

class _TableSheetState extends State<_TableSheet> {
  late final TextEditingController _number = TextEditingController(
    text: widget.table == null ? '' : '${widget.table!.number}',
  );
  late final TextEditingController _name = TextEditingController(
    text: widget.table?.name ?? '',
  );

  late int _capacity = widget.table?.capacity ?? 4;
  late TableStatus _status = widget.table?.status ?? TableStatus.available;

  bool _busy = false;
  String? _numberError;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.table == null;

    return AppSheet(
      title: isNew ? context.t('addTable') : widget.table!.label,
      footer: Row(
        children: <Widget>[
          if (widget.onDelete != null) ...<Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: Text(context.t('delete')),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            flex: 2,
            child: GradientButton(
              label: context.t('save'),
              icon: Icons.check_rounded,
              height: 50,
              loading: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _number,
            enabled: !_busy && isNew,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.t('tableNumber'),
              errorText: _numberError,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: '${context.t('name')} (${context.t('optional')})',
              hintText: 'VIP Hall',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.t('capacity'),
                  style: context.texts.titleMedium,
                ),
              ),
              QuantityStepper(
                quantity: _capacity,
                onIncrement: () =>
                    setState(() => _capacity = (_capacity + 1).clamp(1, 100)),
                onDecrement: () =>
                    setState(() => _capacity = (_capacity - 1).clamp(1, 100)),
              ),
            ],
          ),
          if (!isNew) ...<Widget>[
            const SizedBox(height: AppSpacing.xl),
            Text(context.t('status'), style: context.texts.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: TableStatus.values.map((TableStatus s) {
                final bool selected = s == _status;
                // An occupied table is occupied because an order says so;
                // flipping it by hand would orphan that order.
                final bool locked = s == TableStatus.occupied;

                return Opacity(
                  opacity: locked && !selected ? 0.4 : 1,
                  child: GestureDetector(
                    onTap: locked ? null : () => setState(() => _status = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm + 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? s.color : context.palette.card,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(
                          color: selected ? s.color : context.palette.border,
                        ),
                      ),
                      child: Text(
                        _statusLabel(context, s),
                        style: context.texts.titleSmall?.copyWith(
                          color: selected
                              ? Colors.white
                              : context.palette.subtext,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              _error!,
              style: context.texts.bodyMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(BuildContext context, TableStatus s) =>
      switch (s) {
        TableStatus.available => context.t('available'),
        TableStatus.occupied => context.t('preparing'),
        TableStatus.reserved => context.t('pending'),
        TableStatus.disabled => context.t('inactive'),
      };

  Future<void> _save() async {
    if (_busy) return;

    final int number = int.tryParse(_number.text.trim()) ?? 0;
    if (number <= 0) {
      setState(() => _numberError = context.t('required'));

      return;
    }

    setState(() {
      _busy = true;
      _numberError = null;
      _error = null;
    });

    try {
      await widget.onSave(
        DiningTable(
          id: widget.table?.id ?? -1,
          restaurantId: widget.table?.restaurantId ?? 0,
          number: number,
          capacity: _capacity,
          name: _name.text.trim(),
          status: _status,
          active: _status != TableStatus.disabled,
        ),
      );

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _numberError = e.fields['table_number'];
        _error = e.fields.isEmpty ? e.message : null;
      });
    }
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.onDelete!();
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({required this.status, required this.count});

  final TableStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: context.texts.titleLarge?.copyWith(fontSize: 16),
          ),
          Text(
            _label(context, status),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.labelSmall?.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  static String _label(BuildContext context, TableStatus s) => switch (s) {
    TableStatus.available => context.t('available'),
    TableStatus.occupied => context.t('preparing'),
    TableStatus.reserved => context.t('pending'),
    TableStatus.disabled => context.t('inactive'),
  };
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.order,
    required this.onTap,
  });

  final DiningTable table;
  final RestaurantOrder? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = table.status.color;
    final bool occupied = table.status == TableStatus.occupied;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md - 2),
      color: occupied
          ? color.withValues(alpha: context.isDark ? 0.16 : 0.07)
          : null,
      borderColor: occupied ? color.withValues(alpha: 0.35) : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.table_restaurant_rounded, size: 17, color: color),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ),
          const Spacer(),
          Text(
            table.name.isNotEmpty
                ? table.name
                : table.number.toString().padLeft(2, '0'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleLarge?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Icon(
                Icons.person_rounded,
                size: 12,
                color: context.palette.subtext,
              ),
              const SizedBox(width: 2),
              Text('${table.capacity}', style: context.texts.bodySmall),
              const Spacer(),
              if (order != null)
                Flexible(
                  child: Text(
                    Fmt.compact(order!.total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.labelSmall?.copyWith(color: color),
                  ),
                ),
            ],
          ),
          if (order != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            StatusChip(
              label: Fmt.orderNo(order!.number),
              color: color,
              dense: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _TablesVm {
  const _TablesVm({
    required this.tables,
    required this.countOf,
    required this.orderFor,
    required this.canManage,
    required this.onSave,
    required this.onDelete,
  });

  factory _TablesVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _TablesVm(
      tables: s.tables.tables,
      countOf: (TableStatus st) =>
          s.tables.tables.where((DiningTable t) => t.status == st).length,
      orderFor: (DiningTable t) => s.orders.byId(t.currentOrderId),
      canManage: s.auth.can(Permission.tablesManage),
      onSave: (DiningTable t) => Effects.saveTable(store, t),
      onDelete: (int id) => Effects.deleteTable(store, id),
    );
  }

  final List<DiningTable> tables;
  final int Function(TableStatus) countOf;
  final RestaurantOrder? Function(DiningTable) orderFor;
  final bool canManage;
  final Future<void> Function(DiningTable) onSave;
  final Future<void> Function(int) onDelete;
}
