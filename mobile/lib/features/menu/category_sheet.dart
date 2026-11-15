import 'package:flutter/material.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../data/api/api_client.dart';
import '../../data/models/menu.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/buttons.dart';

/// Create or edit a menu category.
///
/// Emoji and colour are part of the record rather than decoration: they are
/// what makes a category recognisable at a glance in the POS chip row, which
/// is where staff actually use them.
Future<void> showCategorySheet(
  BuildContext context, {
  MenuCategory? category,
  required Future<void> Function(MenuCategory) onSave,
}) {
  return showAppSheet<void>(
    context,
    builder: (BuildContext context) =>
        _CategorySheet(category: category, onSave: onSave),
  );
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({this.category, required this.onSave});

  final MenuCategory? category;
  final Future<void> Function(MenuCategory) onSave;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  static const List<String> _emojis = <String>[
    '🍔',
    '🍕',
    '🍗',
    '🥤',
    '🍰',
    '🍟',
    '🥘',
    '🍝',
    '🌯',
    '🥗',
    '🍚',
    '☕',
    '🍨',
    '🧃',
    '🍜',
    '🍽️',
  ];

  static const List<Color> _colors = AppColors.series;

  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.category?.description ?? '',
  );

  late String _emoji = widget.category?.emoji ?? '🍽️';
  late Color _color = widget.category?.color ?? AppColors.primary;
  late bool _active = widget.category?.active ?? true;

  bool _busy = false;
  String? _nameError;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: widget.category == null
          ? context.t('addCategory')
          : context.t('edit'),
      footer: GradientButton(
        label: context.t('save'),
        icon: Icons.check_rounded,
        loading: _busy,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: context.isDark ? 0.24 : 0.13),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(
                child: Text(_emoji, style: const TextStyle(fontSize: 34)),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          TextField(
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: context.t('name'),
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _description,
            enabled: !_busy,
            decoration: InputDecoration(labelText: context.t('description')),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text(context.t('items'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _emojis.map((String e) {
              final bool selected = e == _emoji;

              return GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? _color.withValues(alpha: 0.16)
                        : context.palette.muted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: selected ? _color : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text(context.t('appearance'), style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: _colors.map((Color c) {
              final bool selected = c.toARGB32() == _color.toARGB32();

              return GestureDetector(
                onTap: () => setState(() => _color = c),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? context.palette.text
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.md),

          SwitchListTile.adaptive(
            value: _active,
            onChanged: _busy ? null : (bool v) => setState(() => _active = v),
            contentPadding: EdgeInsets.zero,
            title: Text(context.t('active'), style: context.texts.titleSmall),
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.success,
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
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

  Future<void> _save() async {
    if (_busy) return;

    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = context.t('required'));

      return;
    }

    setState(() {
      _busy = true;
      _nameError = null;
      _error = null;
    });

    try {
      await widget.onSave(
        MenuCategory(
          // Non-positive id means "not saved yet"; the server assigns it.
          id: widget.category?.id ?? -1,
          restaurantId: widget.category?.restaurantId ?? 0,
          name: name,
          emoji: _emoji,
          color: _color,
          description: _description.text.trim(),
          active: _active,
          sortOrder: widget.category?.sortOrder ?? 0,
        ),
      );

      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = e.fields['name'];
        _error = e.fields.isEmpty ? e.message : null;
      });
    }
  }
}
