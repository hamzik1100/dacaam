import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/menu.dart';
import '../../data/models/order.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/states/pos_state.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/food_thumb.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'checkout_sheet.dart';
import 'save_draft_sheet.dart';

/// The operational heart of the app: pick items fast, review, check out.
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _PosVm>(
      converter: _PosVm.from,
      builder: (BuildContext context, _PosVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _PosHeader(vm: vm),

                // Said here rather than at checkout.
                //
                // Nothing can be sold until a till is open, and finding that
                // out only after building a ten-item cart is a poor way to
                // learn it. The cart survives either way, but the cashier
                // should not have to reach the last step to be told.
                if (!vm.tillOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      0,
                      AppSpacing.gutter,
                      AppSpacing.md,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.lock_rounded,
                            size: 18,
                            color: AppColors.danger,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              context.t('tillClosedSellBlocked'),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.danger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.md,
                  ),
                  child: SegmentedTabs(
                    labels: <String>[context.t('navMenu'), context.t('cart')],
                    index: vm.tabIndex,
                    onChanged: vm.onTabChanged,
                    badges: <int, int>{1: vm.cartCount},
                  ),
                ),
                Expanded(
                  child: vm.tabIndex == 0 ? _MenuTab(vm: vm) : _CartTab(vm: vm),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PosHeader extends StatelessWidget {
  const _PosHeader({required this.vm});

  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(context.t('navPos'), style: context.texts.headlineSmall),
                Text(
                  vm.restaurantName,
                  style: context.texts.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          BouncePulse(
            trigger: vm.cartCount,
            child: SoftIconButton(
              icon: Icons.shopping_bag_outlined,
              badgeCount: vm.cartCount,
              onPressed: () => vm.onTabChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- menu tab

class _MenuTab extends StatelessWidget {
  const _MenuTab({required this.vm});

  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.status.isLoading) {
      return const SingleChildScrollView(child: GridSkeleton());
    }

    final List<MenuItem> items = vm.visibleItems;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: AppSearchField(
            hint: context.t('searchMenuItems'),
            initialValue: vm.query,
            onChanged: vm.onSearch,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ChipSelector<int?>(
          values: <int?>[null, ...vm.categories.map((MenuCategory c) => c.id)],
          selected: vm.categoryId,
          labelOf: (int? id) => id == null
              ? context.t('all')
              : vm.categories.firstWhere((MenuCategory c) => c.id == id).name,
          colorOf: (int? id) => id == null
              ? AppColors.primary
              : vm.categories.firstWhere((MenuCategory c) => c.id == id).color,
          onSelected: vm.onCategorySelected,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: context.t('noItemsFound'),
                  message: context.t('noItemsFoundBody'),
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    vm.cartCount > 0 ? 104 : AppSpacing.xxl,
                  ),
                  // Three across, not two. At two, a phone showed six items
                  // and every one of them was a poster — a POS grid is a
                  // keyboard, and the fewer taps of scrolling between the
                  // dishes somebody rings up all day the better.
                  //
                  // The ratio drops with the width: a narrower column needs to
                  // be proportionally taller for the picture to stay square
                  // above two lines of text.
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final MenuItem item = items[i];
                    return Entrance(
                      index: i,
                      stagger: const Duration(milliseconds: 28),
                      child: _ProductCard(
                        item: item,
                        category: vm.categoryOf(item.categoryId),
                        quantity: vm.quantityOf(item.id),
                        onAdd: () => vm.onAdd(item),
                      ),
                    );
                  },
                ),
        ),
        if (vm.cartCount > 0) _CartSummaryBar(vm: vm),
      ],
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.category,
    required this.quantity,
    required this.onAdd,
  });

  final MenuItem item;
  final MenuCategory? category;
  final int quantity;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final Color tint = category?.color ?? AppColors.primary;
    final bool disabled = !item.available;

    return PressableScale(
      onTap: disabled ? null : onAdd,
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.xs + 2),
          onTap: disabled ? null : onAdd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: FoodThumb(
                        emoji: item.emoji,
                        imageUrl: item.imageUrl,
                        tint: tint,
                        radius: 12,
                      ),
                    ),
                    if (quantity > 0)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '×$quantity',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (disabled)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: StatusChip(
                          label: context.t('outOfStock'),
                          color: AppColors.danger,
                          dense: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs + 2),
              // Two lines for the name at this width. "Chicken Shawarma Large"
              // truncated to "Chicken Sh..." on every card is a grid nobody can
              // read at a glance, which is the only way it gets read.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelLarge?.copyWith(height: 1.15),
                ),
              ),
              const Spacer(),
              // The price alone on the last line. The whole card is already the
              // add button — a second one beside the price was 30 points of
              // width spent saying what the tap target behind it already said.
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 2),
                child: Text(
                  Fmt.money(item.price),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall?.copyWith(
                    color: disabled ? context.palette.subtext : AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.vm});

  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.palette.card,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: GradientButton(
        label: context.tp('itemsCount', <String, String>{
          'n': '${vm.cartCount}',
        }),
        icon: Icons.shopping_basket_rounded,
        onPressed: () => vm.onTabChanged(1),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              Fmt.money(vm.totals.total),
              style: context.texts.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- cart tab

class _CartTab extends StatelessWidget {
  const _CartTab({required this.vm});

  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.lines.isEmpty) {
      return EmptyState(
        icon: Icons.shopping_basket_outlined,
        title: context.t('emptyCartTitle'),
        message: context.t('emptyCartBody'),
        actionLabel: context.t('browseMenu'),
        onAction: () => vm.onTabChanged(0),
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              0,
              AppSpacing.gutter,
              AppSpacing.lg,
            ),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.tp('itemsCount', <String, String>{
                        'n': '${vm.cartCount}',
                      }),
                      style: context.texts.titleLarge,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmClear(context, vm),
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: Text(context.t('clear')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ...List<Widget>.generate(vm.lines.length, (int i) {
                final OrderLine line = vm.lines[i];
                return Entrance(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Dismissible(
                      key: ValueKey<int>(line.itemId),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) => vm.onRemove(line.itemId),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: AppSpacing.xl),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.12),
                          borderRadius: AppRadius.card,
                        ),
                        child: const Icon(
                          Icons.delete_rounded,
                          color: AppColors.danger,
                        ),
                      ),
                      child: _CartLineTile(line: line, vm: vm),
                    ),
                  ),
                );
              }),
              const SizedBox(height: AppSpacing.sm),
              _TotalsCard(vm: vm),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.palette.card,
            border: Border(top: BorderSide(color: context.palette.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GradientButton(
                label: context.t('checkout'),
                icon: Icons.arrow_forward_rounded,
                onPressed: () => showCheckoutSheet(context),
                trailing: Text(
                  Fmt.money(vm.totals.total),
                  style: context.texts.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Parking a cart is a normal part of service — a customer steps
              // away, a phone order is taken — so it sits beside Checkout
              // rather than being buried in a menu.
              OutlinedButton.icon(
                onPressed: () async {
                  final bool? saved = await showSaveDraftSheet(context);
                  if ((saved ?? false) && context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(context.t('done'))));
                  }
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(context.t('saveAsDraft')),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, _PosVm vm) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('clear')),
        content: Text(context.t('emptyCartBody')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('confirm')),
          ),
        ],
      ),
    );
    if (ok ?? false) vm.onClear();
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.vm});

  final OrderLine line;
  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md - 2),
      child: Row(
        children: <Widget>[
          FoodThumb(
            emoji: line.emoji,
            imageUrl: line.imageUrl,
            size: 50,
            radius: 12,
            tint: vm.tintForItem(line.itemId),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${Fmt.number(line.unitPrice)} × ${line.quantity}',
                  style: context.texts.bodySmall,
                ),
                const SizedBox(height: 3),
                Text(
                  Fmt.money(line.total),
                  style: context.texts.titleSmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          QuantityStepper(
            quantity: line.quantity,
            onIncrement: () => vm.onIncrement(line.itemId),
            onDecrement: () => vm.onDecrement(line.itemId),
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.vm});

  final _PosVm vm;

  @override
  Widget build(BuildContext context) {
    final CartTotals t = vm.totals;
    return AppCard(
      child: Column(
        children: <Widget>[
          DetailRow(label: context.t('subtotal'), value: Fmt.money(t.subtotal)),
          if (t.discount > 0)
            DetailRow(
              label: context.t('discount'),
              value: '- ${Fmt.money(t.discount)}',
              valueColor: AppColors.danger,
            ),
          if (vm.taxEnabled)
            DetailRow(
              label: '${context.t('tax')} (${Fmt.decimal(vm.taxRate)}%)',
              value: Fmt.money(t.tax),
            ),
          if (t.packaging > 0)
            DetailRow(
              label: context.t('packagingFee'),
              value: Fmt.money(t.packaging),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: DashedDivider(),
          ),
          DetailRow(
            label: context.t('total'),
            value: Fmt.money(t.total),
            bold: true,
            valueColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- viewmodel

class _PosVm {
  const _PosVm({
    required this.tillOpen,
    required this.status,
    required this.restaurantName,
    required this.query,
    required this.categoryId,
    required this.tabIndex,
    required this.categories,
    required this.visibleItems,
    required this.lines,
    required this.cartCount,
    required this.totals,
    required this.taxEnabled,
    required this.taxRate,
    required this.onSearch,
    required this.onCategorySelected,
    required this.onTabChanged,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onClear,
    required this.quantityOf,
    required this.categoryOf,
  });

  factory _PosVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _PosVm(
      tillOpen: s.shifts.isOpen,
      status: s.menu.status,
      restaurantName: s.restaurant.restaurant?.name ?? '',
      query: s.pos.query,
      categoryId: s.pos.categoryId,
      tabIndex: s.pos.tabIndex,
      categories: s.categories.categories,
      visibleItems: s.pos.filter(s.menu.items),
      lines: s.cart.lines,
      cartCount: s.cart.itemCount,
      totals: s.cartTotals,
      taxEnabled: s.settings.taxEnabled,
      taxRate: s.settings.taxRate,
      onSearch: (String q) => store.dispatch(PosSearchChanged(q)),
      onCategorySelected: (int? id) => store.dispatch(PosCategorySelected(id)),
      onTabChanged: (int i) => store.dispatch(PosTabChanged(i)),
      onAdd: (MenuItem item) => store.dispatch(CartItemAdded(item)),
      onIncrement: (int id) => store.dispatch(CartItemIncremented(id)),
      onDecrement: (int id) => store.dispatch(CartItemDecremented(id)),
      onRemove: (int id) => store.dispatch(CartItemRemoved(id)),
      onClear: () => store.dispatch(const CartCleared()),
      quantityOf: s.cart.quantityOf,
      categoryOf: s.categories.byId,
    );
  }

  final Status status;
  final String restaurantName;
  final String query;
  final int? categoryId;
  final int tabIndex;
  final List<MenuCategory> categories;
  final List<MenuItem> visibleItems;
  final List<OrderLine> lines;
  /// Whether a till is open. Selling is refused without one.
  final bool tillOpen;

  final int cartCount;
  final CartTotals totals;
  final bool taxEnabled;
  final double taxRate;

  final ValueChanged<String> onSearch;
  final ValueChanged<int?> onCategorySelected;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<MenuItem> onAdd;
  final ValueChanged<int> onIncrement;
  final ValueChanged<int> onDecrement;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear;
  final int Function(int) quantityOf;
  final MenuCategory? Function(int) categoryOf;

  Color tintForItem(int itemId) {
    for (final MenuItem i in visibleItems) {
      if (i.id == itemId) {
        return categoryOf(i.categoryId)?.color ?? AppColors.primary;
      }
    }
    return AppColors.primary;
  }
}
