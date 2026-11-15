import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/enums.dart';
import '../../data/models/menu.dart';
import '../../data/api/api_client.dart';
import '../../redux/app_state.dart';
import '../../redux/effects.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';
import '../../widgets/food_thumb.dart';

/// Create / edit / view a menu item.
///
/// `readOnly` reuses the same layout for the "View" action so the fields a
/// manager sees never drift between viewing and editing.
Future<void> showMenuItemSheet(
  BuildContext context, {
  MenuItem? item,
  bool readOnly = false,
}) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) =>
        _MenuItemSheet(item: item, readOnly: readOnly),
  );
}

class _MenuItemSheet extends StatefulWidget {
  const _MenuItemSheet({this.item, this.readOnly = false});

  final MenuItem? item;
  final bool readOnly;

  @override
  State<_MenuItemSheet> createState() => _MenuItemSheetState();
}

class _MenuItemSheetState extends State<_MenuItemSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.item?.name ?? '',
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.item == null ? '' : widget.item!.price.toStringAsFixed(0),
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item?.description ?? '',
  );

  late int? _categoryId = widget.item?.categoryId;
  late bool _available = widget.item?.available ?? true;
  late bool _packaging = widget.item?.applyPackagingFee ?? true;

  String? _nameError;
  String? _priceError;
  String? _categoryError;
  String? _saveError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _ItemVm>(
      converter: _ItemVm.from,
      builder: (BuildContext context, _ItemVm vm) {
        final bool editable = !widget.readOnly && vm.canEdit;
        final MenuCategory? category = _categoryId == null
            ? null
            : vm.categoryOf(_categoryId!);

        return AppSheet(
          title: widget.item == null
              ? context.t('addItem')
              : widget.readOnly
              ? widget.item!.name
              : context.t('editItem'),
          footer: editable
              ? GradientButton(
                  label: context.t('save'),
                  icon: Icons.check_rounded,
                  loading: _busy,
                  onPressed: () => _save(vm),
                )
              : OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(context.t('close')),
                ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: _PhotoPicker(
                  item: widget.item,
                  tint: category?.color ?? AppColors.primary,
                  enabled: editable && widget.item != null,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              _Label(text: context.t('name'), required: true),
              TextField(
                controller: _name,
                enabled: editable,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Chicken Burger',
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _Label(text: context.t('category'), required: true),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: vm.categories.map((MenuCategory c) {
                  final bool selected = c.id == _categoryId;
                  return Material(
                    color: selected ? c.color : context.palette.card,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: editable
                          ? () => setState(() {
                              _categoryId = c.id;
                              _categoryError = null;
                            })
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(
                            color: selected ? c.color : context.palette.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(c.emoji, style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(
                              c.name,
                              style: context.texts.titleSmall?.copyWith(
                                color: selected
                                    ? Colors.white
                                    : context.palette.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_categoryError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _categoryError!,
                    style: context.texts.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),

              _Label(text: context.t('price'), required: true),
              TextField(
                controller: _price,
                enabled: editable,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '35000',
                  prefixText: '${vm.currencyPrefix}  ',
                  errorText: _priceError,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _Label(text: context.t('description')),
              TextField(
                controller: _description,
                enabled: editable,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Chicken burger with fries',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile.adaptive(
                      value: _available,
                      onChanged: editable
                          ? (bool v) => setState(() => _available = v)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.t('availableForSale'),
                        style: context.texts.titleSmall,
                      ),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                    ),
                    Divider(height: 1, color: context.palette.border),
                    SwitchListTile.adaptive(
                      value: _packaging,
                      onChanged: editable
                          ? (bool v) => setState(() => _packaging = v)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.t('applyPackagingFee'),
                        style: context.texts.titleSmall,
                      ),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              if (_saveError != null) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _saveError!,
                  style: context.texts.bodyMedium?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _save(_ItemVm vm) async {
    if (_busy) return;

    // Same three rules the API enforces: a name, a category, and a price > 0.
    // Checked here for a fast answer, and again on the server for a true one.
    final String name = _name.text.trim();
    final double price = double.tryParse(_price.text.replaceAll(',', '')) ?? 0;

    setState(() {
      _nameError = name.isEmpty ? context.t('required') : null;
      _priceError = price <= 0 ? context.t('required') : null;
      _categoryError = _categoryId == null ? context.t('required') : null;
      _saveError = null;
    });
    if (_nameError != null || _priceError != null || _categoryError != null) {
      return;
    }

    setState(() => _busy = true);

    try {
      await vm.onSave(
        MenuItem(
          // A non-positive id is the sentinel for "not saved yet"; the server
          // assigns the real one.
          id: widget.item?.id ?? -1,
          restaurantId: vm.restaurantId,
          categoryId: _categoryId!,
          name: name,
          price: price,
          description: _description.text.trim(),
          imageUrl: widget.item?.imageUrl,
          emoji:
              widget.item?.emoji ?? vm.categoryOf(_categoryId!)?.emoji ?? '🍽️',
          available: _available,
          applyPackagingFee: _packaging,
        ),
        // A price change on a live menu is the single most audited event in
        // the module, so say why when one is being edited.
        widget.item != null && widget.item!.price != price
            ? 'Price update'
            : null,
      );

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = e.fields['name'];
        _priceError = e.fields['price'];
        _categoryError = e.fields['category_id'];
        _saveError = e.fields.isEmpty ? e.message : null;
      });
    }
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Text(text, style: context.texts.titleMedium),
          if (required)
            Text(
              ' *',
              style: context.texts.titleMedium?.copyWith(
                color: AppColors.danger,
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemVm {
  const _ItemVm({
    required this.categories,
    required this.canEdit,
    required this.currencyPrefix,
    required this.restaurantId,
    required this.onSave,
    required this.categoryOf,
  });

  factory _ItemVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _ItemVm(
      categories: s.categories.categories,
      canEdit: s.auth.can(Permission.menuEdit),
      currencyPrefix: s.settings.currencyPrefix,
      restaurantId: s.restaurant.restaurant?.id ?? 0,
      onSave: (MenuItem item, String? reason) =>
          Effects.saveMenuItem(store, item, reason: reason),
      categoryOf: s.categories.byId,
    );
  }

  final List<MenuCategory> categories;
  final bool canEdit;
  final String currencyPrefix;
  final int restaurantId;
  final Future<void> Function(MenuItem, String?) onSave;
  final MenuCategory? Function(int) categoryOf;
}

/// The item's photograph, with a way to replace or remove it.
///
/// Only offered on an item that already exists: the picture is stored against
/// an id, and there is nothing to attach it to until the item has been saved
/// once. On a new item this shows the emoji and says so.
class _PhotoPicker extends StatefulWidget {
  const _PhotoPicker({
    required this.item,
    required this.tint,
    required this.enabled,
  });

  final MenuItem? item;
  final Color tint;
  final bool enabled;

  @override
  State<_PhotoPicker> createState() => _PhotoPickerState();
}

class _PhotoPickerState extends State<_PhotoPicker> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            FoodThumb(
              emoji: widget.item?.emoji ?? '🍽️',
              imageUrl: widget.item?.imageUrl,
              size: 96,
              radius: 22,
              tint: widget.tint,
            ),
            if (_busy)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // A picture is stored against an id, so there is nothing to attach it
        // to until the item has been saved once. Saying so beats a row of
        // buttons that quietly are not there.
        if (!widget.enabled && widget.item == null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.t('photoAfterSave'),
            textAlign: TextAlign.center,
            style: context.texts.labelSmall?.copyWith(
              color: context.palette.subtext,
            ),
          ),
        ],
        if (widget.enabled) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          // Wrap, not Row: two labelled buttons and a delete icon are wider
          // than a small phone once the Somali labels are in, and a button
          // past the edge is one nobody can press.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded, size: 17),
                label: Text(context.t('takePhoto')),
              ),
              TextButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_rounded, size: 17),
                label: Text(context.t('choosePhoto')),
              ),
              if (widget.item?.imageUrl != null)
                IconButton(
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  color: AppColors.danger,
                  tooltip: context.t('delete'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pick(ImageSource source) async {
    // The resize happens here, in the picker, before a single byte is sent.
    // maxWidth/maxHeight and imageQuality are handled natively, so a 4 MB
    // camera frame becomes roughly 100 KB without a Dart image library and
    // without holding the full bitmap in memory.
    //
    // It is also the difference between a two-second upload and a
    // thirty-second one on the connection this runs on, paid for by the
    // megabyte.
    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (picked == null || !mounted) return;

    setState(() => _busy = true);

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await Effects.setMenuItemImage(
        store,
        widget.item!.id,
        base64Encode(await picked.readAsBytes()),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);

    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      await Effects.setMenuItemImage(store, widget.item!.id, null);
    } on ApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}