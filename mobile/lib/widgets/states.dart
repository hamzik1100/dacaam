import 'package:flutter/material.dart';

import '../core/i18n/app_strings.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import 'buttons.dart';

/// Premium empty state: soft icon medallion, a title, one line of guidance and
/// at most one action. Used everywhere a list can legitimately be empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.tint = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: compact ? AppSpacing.xl : AppSpacing.xxxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 64 : 84,
              height: compact ? 64 : 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    tint.withValues(alpha: context.isDark ? 0.26 : 0.16),
                    tint.withValues(alpha: context.isDark ? 0.10 : 0.05),
                  ],
                ),
              ),
              child: Icon(icon, size: compact ? 28 : 36, color: tint),
            ),
            SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleLarge,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium?.copyWith(
                  color: palette.subtext,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              GradientButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                icon: Icons.add_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state with a retry affordance. Never a bare exception string.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({super.key, this.message, this.onRetry});

  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.danger.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.wifi_tethering_error_rounded,
                size: 36,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(context.t('errorTitle'), style: context.texts.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message ?? context.t('errorBody'),
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.t('retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder for modules that land in a later phase. Honest rather than a
/// dead link — it names the module and gets the user back.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.icon,
    this.note,
  });

  final String title;
  final IconData icon;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(
        icon: icon,
        title: context.t('comingSoon'),
        message: note ?? context.t('comingSoonBody'),
      ),
    );
  }
}
