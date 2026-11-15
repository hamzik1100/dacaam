import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/api/api_client.dart';
import '../../data/models/menu.dart';
import '../../data/models/order.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/food_thumb.dart';

/// Edits the lines of an order that is still open.
///
/// The totals shown while editing are an estimate. The server reprices from
/// stored menu prices and returns the authoritative order, so an item whose
/// price changed since the order was taken is charged at the price the
/// restaurant actually set — not at whatever this screen last saw.
Future<void> showOrderEditSheet(BuildContext context, int orderId) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) => _OrderEditSheet(orderId: orderId),
  );
}

class _OrderEditSheet extends StatefulWidget {
  const _OrderEditSheet({required this.orderId});

  final int orderId;

  @override
  State<_OrderEditSheet> createState() => _OrderEditSheetState();
}

class _OrderEditSheetState extends State<_OrderEditSheet> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _search = TextEditingController();

  List<OrderLine>? _lines;
  bool _adding = false;
  bool _busy = false;
  String? _reasonError;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _EditVm>(
      converter: (Store<AppState> store) => _EditVm.from(store, widget.orderId),
      builder: (BuildContext context, _EditVm vm) {
        final RestaurantOrder? order = vm.order;
        if (order == null) return const SizedBox.shrink();

        // Seeded once from the order, then owned by this sheet: rebuilding from
        // the store on every frame would throw away edits in progress.
        _lines ??= List<OrderLine>.of(order.lines);

        return AppSheet(
          title: '${context.t('edit')} · #${order.number}',
          footer: _footer(context, vm, order),
          child: _adding ? _picker(context, vm) : _editor(context, order),
        );
      },
    );
  }

  // ------------------------------------------------------------- the lines

  Widget _editor(BuildContext context, RestaurantOrder order) {
    final List<OrderLine> lines = _lines!;
    final double subtotal = lines.fold<double>(
      0,
      (double sum, OrderLine l) => sum + (l.unitPrice * l.quantity),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Text(
              context.t('emptyLines'),
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(
                color: context.palette.subtext,
              ),
            ),
          )
        else
          ...lines.map((OrderLine line) => _row(context, line)),

        const SizedBox(height: AppSpacing.sm),

        OutlinedButton.icon(
          onPressed: () => setState(() => _adding = true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(context.t('addItem')),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(context.t('subtotal'), style: context.texts.bodyMedium),
            Text(
              Fmt.money(subtotal),
              style: context.texts.titleSmall?.copyWith(
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            context.t('serverRecalculates'),
            style: context.texts.bodySmall?.copyWith(
              color: context.palette.subtext,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Required, and the API rejects a blank one too. An audit row that says
        // a quantity moved 2 → 3 with no reason is the one nobody can act on.
        Text(context.t('reason'), style: context.texts.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _reason,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('editReasonHint'),
            errorText: _reasonError,
          ),
          onChanged: (_) {
            if (_reasonError != null) setState(() => _reasonError = null);
          },
        ),

        if (_error != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: context.texts.bodySmall?.copyWith(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, OrderLine line) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          FoodThumb(emoji: line.emoji, imageUrl: line.imageUrl, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.name,
                  style: context.texts.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  Fmt.money(line.unitPrice),
                  style: context.texts.bodySmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: line.quantity > 1
                ? Icons.remove_rounded
                : Icons.delete_outline_rounded,
            danger: line.quantity == 1,
            onTap: () => setState(() {
              if (line.quantity > 1) {
                _replace(line, line.quantity - 1);
              } else {
                _lines!.removeWhere((OrderLine l) => l.itemId == line.itemId);
              }
            }),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${line.quantity}',
              textAlign: TextAlign.center,
              style: context.texts.titleSmall,
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            onTap: () => setState(() => _replace(line, line.quantity + 1)),
          ),
        ],
      ),
    );
  }

  void _replace(OrderLine line, int quantity) {
    final int i = _lines!.indexWhere((OrderLine l) => l.itemId == line.itemId);
    if (i >= 0) _lines![i] = line.copyWith(quantity: quantity);
  }

  // ------------------------------------------------------------ add an item

  Widget _picker(BuildContext context, _EditVm vm) {
    final String q = _search.text.trim().toLowerCase();
    final List<MenuItem> results = vm.menu
        .where(
          (MenuItem i) =>
              i.available && (q.isEmpty || i.name.toLowerCase().contains(q)),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _search,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.t('search'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: results.length,
            itemBuilder: (BuildContext context, int i) {
              final MenuItem item = results[i];

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: FoodThumb(
                  emoji: item.emoji,
                  imageUrl: item.imageUrl,
                  size: 40,
                ),
                title: Text(item.name, style: context.texts.titleSmall),
                subtitle: Text(
                  Fmt.money(item.price),
                  style: context.texts.bodySmall,
                ),
                trailing: const Icon(Icons.add_rounded, size: 20),
                onTap: () => setState(() {
                  final int existing = _lines!.indexWhere(
                    (OrderLine l) => l.itemId == item.id,
                  );
                  if (existing >= 0) {
                    _lines![existing] = _lines![existing].copyWith(
                      quantity: _lines![existing].quantity + 1,
                    );
                  } else {
                    _lines!.add(OrderLine.fromMenuItem(item));
                  }
                  _adding = false;
                  _search.clear();
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- footer

  Widget _footer(BuildContext context, _EditVm vm, RestaurantOrder order) {
    if (_adding) {
      return OutlinedButton(
        onPressed: () => setState(() {
          _adding = false;
          _search.clear();
        }),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 50),
        ),
        child: Text(context.t('goBack')),
      );
    }

    return GradientButton(
      label: context.t('save'),
      height: 50,
      loading: _busy,
      onPressed: _busy ? null : () => _save(vm),
    );
  }

  /// Takes no BuildContext: it uses the State's own, so the `mounted` check
  /// after the await is the one the analyzer can actually reason about.
  Future<void> _save(_EditVm vm) async {
    final String reason = _reason.text.trim();

    if (reason.length < 3) {
      setState(() => _reasonError = context.t('editReasonRequired'));

      return;
    }

    if (_lines!.isEmpty) {
      setState(() => _error = context.t('emptyLines'));

      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await vm.onSave(_lines!, reason);
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

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: danger ? AppColors.danger : context.palette.border,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: danger ? AppColors.danger : context.palette.text,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ viewmodel

class _EditVm {
  const _EditVm({
    required this.order,
    required this.menu,
    required this.onSave,
  });

  factory _EditVm.from(Store<AppState> store, int orderId) {
    final AppState s = store.state;

    return _EditVm(
      order: s.orders.byId(orderId),
      menu: s.menu.items,
      onSave: (List<OrderLine> lines, String reason) =>
          Effects.updateOrderItems(store, orderId, lines, reason: reason),
    );
  }

  final RestaurantOrder? order;
  final List<MenuItem> menu;
  final Future<void> Function(List<OrderLine>, String) onSave;
}
