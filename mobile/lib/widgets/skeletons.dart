import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import 'app_card.dart';

/// A single shimmering placeholder block.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    final Color base = palette.muted;
    final Color highlight = context.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.85);

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: <Color>[base, highlight, base],
              stops: const <double>[0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Dashboard skeleton: 4 KPI tiles, a chart block and a short list.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.xxxl,
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: _KpiSkeleton()),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: _KpiSkeleton()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            const Expanded(child: _KpiSkeleton()),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: _KpiSkeleton()),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonBox(width: 120, height: 16),
              SizedBox(height: AppSpacing.lg),
              SkeletonBox(height: 140, radius: 12),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const ListSkeleton(rows: 3),
      ],
    );
  }
}

class _KpiSkeleton extends StatelessWidget {
  const _KpiSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SkeletonBox(width: 70, height: 11),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(width: 110, height: 20),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: 48, height: 11),
        ],
      ),
    );
  }
}

/// Generic card-list skeleton used by Orders, Menu and Reports lists.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 5, this.hasThumb = true});

  final int rows;
  final bool hasThumb;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(rows, (int i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                if (hasThumb) ...<Widget>[
                  const SkeletonBox(width: 52, height: 52, radius: 12),
                  const SizedBox(width: AppSpacing.md),
                ],
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SkeletonBox(width: 140, height: 14),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonBox(width: 90, height: 11),
                    ],
                  ),
                ),
                const SkeletonBox(width: 60, height: 24, radius: 12),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Grid skeleton for the POS product wall.
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.82,
      ),
      itemCount: count,
      itemBuilder: (BuildContext context, int i) => const AppCard(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: SkeletonBox(height: double.infinity, radius: 12)),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(width: 100, height: 13),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(width: 70, height: 13),
          ],
        ),
      ),
    );
  }
}
