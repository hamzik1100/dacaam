import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';

/// Section title with an optional right-hand action ("View All").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: context.texts.titleLarge)),
          ?trailing,
          if (trailing == null && actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Small pill used for order status, availability and order type.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.filled = true,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md - 2,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: context.isDark ? 0.20 : 0.11)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          // Flexible + ellipsis so a chip in a tight row degrades gracefully
          // instead of overflowing — Somali status labels are longer than the
          // English ones this component was first sized against.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: dense ? 10.5 : 11.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Up/down percentage indicator. Green up, red down — no other colours.
class DeltaBadge extends StatelessWidget {
  const DeltaBadge({super.key, required this.percent, this.dense = false});

  final double percent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final bool up = percent >= 0;
    final Color color = up ? AppColors.success : AppColors.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: dense ? 11 : 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          '${percent.abs().toStringAsFixed(1)}%',
          style: TextStyle(
            color: color,
            fontSize: dense ? 11 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Horizontal pill selector (POS categories, report ranges, order statuses).
class ChipSelector<T> extends StatelessWidget {
  const ChipSelector({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.colorOf,
    this.countOf,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
    this.height = 38,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final Color Function(T)? colorOf;
  final int? Function(T)? countOf;
  final EdgeInsetsGeometry padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: values.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int i) {
          final T value = values[i];
          final bool isSelected = value == selected;
          final Color accent = colorOf?.call(value) ?? AppColors.primary;
          final int? count = countOf?.call(value);

          return AnimatedContainer(
            duration: AppMotion.fast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isSelected ? accent : palette.card,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: isSelected ? accent : palette.border),
              boxShadow: isSelected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 12,
                        spreadRadius: -4,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onSelected(value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        labelOf(value),
                        style: context.texts.titleSmall?.copyWith(
                          color: isSelected ? Colors.white : palette.subtext,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (count != null) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : palette.muted,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Colors.white
                                  : palette.subtext,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Two-up segmented control (Items/Categories, Menu/Cart, Daily/Monthly).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.badges = const <int, int>{},
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Optional count badge per tab index (used for the POS cart).
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.muted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: List<Widget>.generate(labels.length, (int i) {
          final bool active = i == index;
          final int badge = badges[i] ?? 0;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: AppMotion.normal,
                curve: Curves.easeOut,
                height: 40,
                decoration: BoxDecoration(
                  color: active ? palette.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  boxShadow: active
                      ? <BoxShadow>[
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 8,
                            spreadRadius: -2,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      labels[i],
                      style: context.texts.titleSmall?.copyWith(
                        color: active ? AppColors.primary : palette.subtext,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badge > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Rounded search field with a leading icon and an inline clear button.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.initialValue = '',
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final String initialValue;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return TextField(
      controller: _controller,
      onChanged: (String v) {
        widget.onChanged(v);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      style: context.texts.bodyLarge,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: palette.subtext,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: palette.subtext,
                ),
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// Label / value row used across order details, reports and settings.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: palette.subtext),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(
              label,
              style: context.texts.bodyMedium?.copyWith(color: palette.subtext),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (bold ? context.texts.titleMedium : context.texts.titleSmall)
                      ?.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dashed separator used inside receipt-like summaries.
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double dashWidth = 5;
        const double gap = 4;
        final int count = (constraints.constrainWidth() / (dashWidth + gap))
            .floor();
        return Row(
          mainAxisSize: MainAxisSize.max,
          children: List<Widget>.generate(
            count,
            (_) => Container(
              width: dashWidth,
              height: height,
              margin: const EdgeInsets.only(right: gap),
              color: context.palette.border,
            ),
          ),
        );
      },
    );
  }
}
