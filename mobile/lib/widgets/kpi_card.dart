import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import 'app_card.dart';
import 'common.dart';
import 'count_up.dart';

/// Dashboard / Reports metric tile.
///
/// Layout is fixed across all four tiles — label, animated figure, delta, icon
/// badge — so a row of them scans as a single unit rather than four designs.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.tint,
    this.deltaPercent,
    this.onTap,
    this.animate = true,
  });

  final String label;
  final double value;
  final String Function(double) format;
  final IconData icon;
  final Color tint;
  final double? deltaPercent;
  final VoidCallback? onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelMedium?.copyWith(
                    color: palette.subtext,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: animate
                    ? CountUpText(
                        value: value,
                        format: format,
                        style: context.texts.titleLarge?.copyWith(
                          fontSize: 19,
                          letterSpacing: -0.5,
                        ),
                      )
                    : Text(
                        format(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.titleLarge?.copyWith(
                          fontSize: 19,
                          letterSpacing: -0.5,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Row(
            children: <Widget>[
              if (deltaPercent != null)
                DeltaBadge(percent: deltaPercent!, dense: true),
              const Spacer(),
              IconBadge(
                icon: icon,
                color: tint,
                size: 30,
                iconSize: 16,
                radius: 9,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact metric row used inside analytic cards (no card chrome of its own).
class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 13, color: color ?? palette.subtext),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.labelSmall?.copyWith(
                  color: palette.subtext,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.texts.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
