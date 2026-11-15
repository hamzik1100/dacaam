import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';

/// The base surface of the whole product: white, 16px radius, hairline border,
/// soft ambient shadow. Every panel on every screen is one of these.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderRadius = AppRadius.card,
    this.color,
    this.borderColor,
    this.elevated = true,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Color? color;
  final Color? borderColor;
  final bool elevated;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? palette.card,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor ?? palette.border),
        boxShadow: elevated ? AppShadows.card(context) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Hero surface. Used sparingly — the profile card in More, the featured
/// dashboard tile, the checkout summary. Never more than one per viewport.
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.borderRadius = AppRadius.cardLarge,
    this.gradient = AppColors.brandSoft,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: borderRadius,
        boxShadow: AppShadows.brand(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          splashColor: Colors.white24,
          highlightColor: Colors.white10,
          child: Stack(
            children: <Widget>[
              // Soft light bloom in the corner keeps the flat gradient from
              // looking like a plain colour fill.
              Positioned(
                right: -30,
                top: -40,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded-square icon badge used in KPI cards, list rows and menus.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
    this.iconSize = 19,
    this.radius = 11,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}
