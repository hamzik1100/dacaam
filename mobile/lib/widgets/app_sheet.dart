import 'package:flutter/material.dart';

import '../core/i18n/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';

/// Standard modal bottom sheet: drag handle, title row, scrollable body and a
/// safe-area-aware footer for actions.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    barrierColor: context.palette.overlay,
    builder: builder,
  );
}

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.trailing,
    this.maxHeightFactor = 0.9,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.gutter,
      0,
      AppSpacing.gutter,
      AppSpacing.lg,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final Widget? trailing;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final double maxHeight =
        MediaQuery.sizeOf(context).height * maxHeightFactor;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: AppRadius.sheet,
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(height: AppSpacing.md),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.border,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(title, style: context.texts.headlineSmall),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: context.texts.bodyMedium),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: context.t('close'),
                    style: IconButton.styleFrom(
                      backgroundColor: palette.muted,
                      minimumSize: const Size(38, 38),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(padding: padding, child: child),
          ),
          if (footer != null)
            Container(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.md,
                AppSpacing.gutter,
                AppSpacing.md + MediaQuery.viewPaddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: palette.card,
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

/// Selection row used inside pickers (payment method, waiter, table…).
class SheetOptionTile extends StatelessWidget {
  const SheetOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.tint = AppColors.primary,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color tint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: selected
              ? tint.withValues(alpha: context.isDark ? 0.18 : 0.08)
              : palette.card,
          borderRadius: AppRadius.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                borderRadius: AppRadius.card,
                border: Border.all(
                  color: selected ? tint : palette.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: 20,
                      color: selected ? tint : palette.subtext,
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(label, style: context.texts.titleMedium),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: context.texts.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  AnimatedScale(
                    duration: AppMotion.fast,
                    scale: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: tint,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
