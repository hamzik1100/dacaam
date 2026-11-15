import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/menu.dart';
import '../../redux/actions.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../redux/states/status.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';
import '../../widgets/entrance.dart';
import '../../widgets/food_thumb.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'category_sheet.dart';
import 'menu_item_sheet.dart';

/// Menu management: the item catalogue and the categories that organise it.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _MenuVm>(
      converter: _MenuVm.from,
      builder: (BuildContext context, _MenuVm vm) {
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: <Widget>[
                _Header(vm: vm),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.md,
                  ),
                  child: SegmentedTabs(
                    labels: <String>[
                      context.t('items'),
                      context.t('categories'),
                    ],
                    index: vm.tabIndex,
                    onChanged: vm.onTabChanged,
                  ),
                ),
                Expanded(
                  child: switch (vm.status) {
                    Status.error => ErrorStateView(onRetry: () {}),
                    Status.idle || Status.loading => const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.gutter,
                      ),
                      child: ListSkeleton(),
                    ),
                    Status.ready =>
                      vm.tabIndex == 0
                          ? _ItemsTab(vm: vm)
                          : _CategoriesTab(vm: vm),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.vm});

  final _MenuVm vm;

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
                Text(context.t('navMenu'), style: context.texts.headlineSmall),
                Text(
                  vm.tabIndex == 0
                      ? context.tp('itemsCount', <String, String>{
                          'n': '${vm.allItems.length}',
                        })
                      : '${vm.categories.length} ${context.t('categories').toLowerCase()}',
                  style: context.texts.bodySmall,
                ),
              ],
            ),
          ),
          if (vm.canCreate)
            Material(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                // The button adds whatever the visible tab is about.
                onTap: () => vm.tabIndex == 0
                    ? showMenuItemSheet(context)
                    : showCategorySheet(context, onSave: vm.onSaveCategory),
                child: const SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- items tab

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.vm});

  final _MenuVm vm;

  @override
  Widget build(BuildContext context) {
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
          selected: vm.categoryFilter,
          labelOf: (int? id) => id == null
              ? context.t('all')
              : vm.categories.firstWhere((MenuCategory c) => c.id == id).name,
          colorOf: (int? id) => id == null
              ? AppColors.primary
              : vm.categories.firstWhere((MenuCategory c) => c.id == id).color,
          onSelected: vm.onCategoryFilter,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: vm.items.isEmpty
              ? EmptyState(
                  icon: Icons.restaurant_menu_rounded,
                  title: context.t('noMenuItems'),
                  message: context.t('noMenuItemsBody'),
                  actionLabel: vm.canCreate ? context.t('addItem') : null,
                  onAction: vm.canCreate
                      ? () => showMenuItemSheet(context)
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    0,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  itemCount: vm.items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final MenuItem item = vm.items[i];
                    return Entrance(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _ItemTile(item: item, vm: vm),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.vm});

  final MenuItem item;
  final _MenuVm vm;

  @override
  Widget build(BuildContext context) {
    final MenuCategory? category = vm.categoryOf(item.categoryId);
    final Color tint = category?.color ?? AppColors.primary;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md - 2),
      onTap: () => showMenuItemSheet(context, item: item),
      child: Row(
        children: <Widget>[
          FoodThumb(
            emoji: item.emoji,
            imageUrl: item.imageUrl,
            size: 58,
            radius: 13,
            tint: tint,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(category?.name ?? '', style: context.texts.bodySmall),
                const SizedBox(height: 5),
                Text(
                  Fmt.money(item.price),
                  style: context.texts.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _ItemMenu(item: item, vm: vm),
              const SizedBox(height: AppSpacing.md),
              StatusChip(
                label: item.available
                    ? context.t('available')
                    : context.t('unavailable'),
                color: item.available ? AppColors.success : AppColors.danger,
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({required this.item, required this.vm});

  final MenuItem item;
  final _MenuVm vm;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 19,
        color: context.palette.subtext,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 170),
      position: PopupMenuPosition.under,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
      onSelected: (String value) async {
        switch (value) {
          case 'view':
          case 'edit':
            showMenuItemSheet(context, item: item, readOnly: value == 'view');
          case 'toggle':
            vm.onToggleAvailability(item.id);
          case 'delete':
            await _confirmDelete(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'view',
          child: _MenuRow(
            icon: Icons.visibility_rounded,
            label: context.t('view'),
          ),
        ),
        if (vm.canEdit)
          PopupMenuItem<String>(
            value: 'edit',
            child: _MenuRow(icon: Icons.edit_rounded, label: context.t('edit')),
          ),
        if (vm.canEdit)
          PopupMenuItem<String>(
            value: 'toggle',
            child: _MenuRow(
              icon: item.available
                  ? Icons.visibility_off_rounded
                  : Icons.check_circle_rounded,
              label: item.available
                  ? context.t('unavailable')
                  : context.t('available'),
            ),
          ),
        if (vm.canDelete)
          PopupMenuItem<String>(
            value: 'delete',
            child: _MenuRow(
              icon: Icons.delete_rounded,
              label: context.t('delete'),
              color: AppColors.danger,
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('deleteItemTitle')),
        content: Text('${item.name}\n\n${context.t('deleteItemBody')}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('delete')),
          ),
        ],
      ),
    );
    if (ok ?? false) vm.onDelete(item.id);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: color ?? context.palette.subtext),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: context.texts.titleSmall?.copyWith(color: color)),
      ],
    );
  }
}

// ----------------------------------------------------------- categories tab

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.vm});

  final _MenuVm vm;

  @override
  Widget build(BuildContext context) {
    if (vm.categories.isEmpty) {
      return EmptyState(
        icon: Icons.category_rounded,
        title: context.t('noData'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        0,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      itemCount: vm.categories.length,
      itemBuilder: (BuildContext context, int i) {
        final MenuCategory c = vm.categories[i];
        final int count = vm.countInCategory(c.id);

        return Entrance(
          index: i,
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: AppCard(
              // Opening a category jumps to a pre-filtered Items tab rather
              // than a separate screen — one fewer place to get lost.
              onTap: () => vm.onOpenCategory(c.id),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: c.color.withValues(
                        alpha: context.isDark ? 0.22 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        c.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
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
                                c.name,
                                style: context.texts.titleMedium,
                              ),
                            ),
                            if (!c.active) ...<Widget>[
                              const SizedBox(width: AppSpacing.sm),
                              StatusChip(
                                label: context.t('inactive'),
                                color: AppColors.danger,
                                dense: true,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tp('itemsCount', <String, String>{
                            'n': '$count',
                          }),
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (vm.canEdit)
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert_rounded,
                        size: 19,
                        color: context.palette.subtext,
                      ),
                      position: PopupMenuPosition.under,
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.card,
                      ),
                      onSelected: (String value) async {
                        if (value == 'edit') {
                          await showCategorySheet(
                            context,
                            category: c,
                            onSave: vm.onSaveCategory,
                          );
                        } else if (value == 'delete') {
                          await _confirmDeleteCategory(context, vm, c, count);
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'edit',
                              child: _MenuRow(
                                icon: Icons.edit_rounded,
                                label: context.t('edit'),
                              ),
                            ),
                            if (vm.canDelete)
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: _MenuRow(
                                  icon: Icons.delete_rounded,
                                  label: context.t('delete'),
                                  color: AppColors.danger,
                                ),
                              ),
                          ],
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.palette.subtext,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteCategory(
    BuildContext context,
    _MenuVm vm,
    MenuCategory category,
    int itemCount,
  ) async {
    // The API refuses too, but saying so before the round trip is kinder than
    // an error after it.
    if (itemCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tp('categoryNotEmpty', <String, String>{'n': '$itemCount'}),
          ),
        ),
      );

      return;
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(context.t('deleteItemTitle')),
        content: Text('${category.name}\n\n${context.t('deleteItemBody')}'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('delete')),
          ),
        ],
      ),
    );

    if (ok ?? false) await vm.onDeleteCategory(category.id);
  }
}

// ----------------------------------------------------------------- viewmodel

class _MenuVm {
  const _MenuVm({
    required this.status,
    required this.tabIndex,
    required this.items,
    required this.allItems,
    required this.categories,
    required this.query,
    required this.categoryFilter,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
    required this.onTabChanged,
    required this.onSearch,
    required this.onCategoryFilter,
    required this.onToggleAvailability,
    required this.onDelete,
    required this.onSaveCategory,
    required this.onDeleteCategory,
    required this.onOpenCategory,
    required this.categoryOf,
    required this.countInCategory,
  });

  factory _MenuVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _MenuVm(
      status: s.menu.status,
      tabIndex: s.menu.tabIndex,
      items: s.menu.filtered,
      allItems: s.menu.items,
      categories: s.categories.categories,
      query: s.menu.query,
      categoryFilter: s.menu.categoryFilter,
      canCreate: s.auth.can(Permission.menuCreate),
      canEdit: s.auth.can(Permission.menuEdit),
      canDelete: s.auth.can(Permission.menuDelete),
      onTabChanged: (int i) => store.dispatch(MenuTabChanged(i)),
      onSearch: (String q) => store.dispatch(MenuSearchChanged(q)),
      onCategoryFilter: (int? id) =>
          store.dispatch(MenuCategoryFilterChanged(id)),
      onToggleAvailability: (int id) => Effects.toggleMenuItem(store, id),
      onDelete: (int id) => Effects.deleteMenuItem(store, id),
      onSaveCategory: (MenuCategory c) => Effects.saveCategory(store, c),
      onDeleteCategory: (int id) => Effects.deleteCategory(store, id),
      onOpenCategory: (int id) {
        store.dispatch(MenuCategoryFilterChanged(id));
        store.dispatch(const MenuTabChanged(0));
      },
      categoryOf: s.categories.byId,
      countInCategory: (int id) =>
          s.menu.items.where((MenuItem i) => i.categoryId == id).length,
    );
  }

  final Status status;
  final int tabIndex;
  final List<MenuItem> items;
  final List<MenuItem> allItems;
  final List<MenuCategory> categories;
  final String query;
  final int? categoryFilter;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  final ValueChanged<int> onTabChanged;
  final ValueChanged<String> onSearch;
  final ValueChanged<int?> onCategoryFilter;
  final ValueChanged<int> onToggleAvailability;
  final ValueChanged<int> onDelete;
  final Future<void> Function(MenuCategory) onSaveCategory;
  final Future<void> Function(int) onDeleteCategory;
  final ValueChanged<int> onOpenCategory;
  final MenuCategory? Function(int) categoryOf;
  final int Function(int) countInCategory;
}
