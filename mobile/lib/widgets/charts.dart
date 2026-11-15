import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/utils/formatters.dart';
import '../data/models/analytics.dart';

/// Charts grow in from zero on first paint via a local tween rather than the
/// chart package's own animation, so entrance timing matches the rest of the
/// app and stays stable across fl_chart versions.
class _ChartGrow extends StatelessWidget {
  const _ChartGrow({required this.builder});

  final Widget Function(double t) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AppMotion.chart,
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double t, _) => builder(t),
    );
  }
}

/// Smooth line chart with a gradient fill — the weekly sales hero chart.
class SalesLineChart extends StatefulWidget {
  const SalesLineChart({
    super.key,
    required this.points,
    required this.labels,
    this.height = 168,
    this.onSelected,
    this.showGrid = true,
  });

  final List<SeriesPoint> points;
  final List<String> labels;
  final double height;

  /// Fires with the touched index, or `null` when the touch is released.
  final ValueChanged<int?>? onSelected;
  final bool showGrid;

  @override
  State<SalesLineChart> createState() => _SalesLineChartState();
}

class _SalesLineChartState extends State<SalesLineChart> {
  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (widget.points.isEmpty) return SizedBox(height: widget.height);

    final double maxY = widget.points
        .map((SeriesPoint p) => p.value)
        .reduce((double a, double b) => a > b ? a : b);
    // Head-room above the peak so the tooltip and the top gridline don't clash.
    final double top = maxY * 1.18;
    final double interval = top / 3;

    return SizedBox(
      height: widget.height,
      child: _ChartGrow(
        builder: (double t) => LineChart(
          LineChartData(
            minY: 0,
            maxY: top == 0 ? 1 : top,
            gridData: FlGridData(
              show: widget.showGrid,
              drawVerticalLine: false,
              horizontalInterval: interval == 0 ? 1 : interval,
              getDrawingHorizontalLine: (double value) => FlLine(
                color: palette.border,
                strokeWidth: 1,
                dashArray: <int>[5, 5],
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: interval == 0 ? 1 : interval,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    if (value < interval * 0.5) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        Fmt.compact(value),
                        style: context.texts.labelSmall?.copyWith(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 1,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final int i = value.round();
                    if (i < 0 || i >= widget.labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.labels[i],
                        style: context.texts.labelSmall?.copyWith(
                          fontSize: 10.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              handleBuiltInTouches: true,
              touchCallback: (FlTouchEvent event, LineTouchResponse? response) {
                if (widget.onSelected == null) return;
                if (!event.isInterestedForInteractions ||
                    response?.lineBarSpots == null ||
                    response!.lineBarSpots!.isEmpty) {
                  widget.onSelected!(null);
                  return;
                }
                widget.onSelected!(response.lineBarSpots!.first.spotIndex);
              },
              getTouchedSpotIndicator:
                  (LineChartBarData barData, List<int> indexes) {
                    return indexes.map((int _) {
                      return TouchedSpotIndicatorData(
                        FlLine(color: AppColors.primary, strokeWidth: 1.5),
                        FlDotData(
                          getDotPainter:
                              (
                                FlSpot spot,
                                double percent,
                                LineChartBarData bar,
                                int index,
                              ) => FlDotCirclePainter(
                                radius: 5,
                                color: Colors.white,
                                strokeWidth: 3,
                                strokeColor: AppColors.primary,
                              ),
                        ),
                      );
                    }).toList();
                  },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (LineBarSpot spot) =>
                    context.isDark ? AppColors.mutedDark : AppColors.textLight,
                tooltipBorderRadius: BorderRadius.circular(10),
                tooltipPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                getTooltipItems: (List<LineBarSpot> spots) {
                  return spots.map((LineBarSpot spot) {
                    return LineTooltipItem(
                      Fmt.money(spot.y / (t == 0 ? 1 : t)),
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            lineBarsData: <LineChartBarData>[
              LineChartBarData(
                spots: List<FlSpot>.generate(
                  widget.points.length,
                  (int i) => FlSpot(i.toDouble(), widget.points[i].value * t),
                ),
                isCurved: true,
                curveSmoothness: 0.32,
                preventCurveOverShooting: true,
                barWidth: 3,
                gradient: AppColors.brand,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      AppColors.primary.withValues(alpha: 0.28),
                      AppColors.secondary.withValues(alpha: 0.02),
                    ],
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

/// Rounded bar chart — Reports "Sales Overview" and hourly breakdowns.
class SalesBarChart extends StatelessWidget {
  const SalesBarChart({
    super.key,
    required this.points,
    required this.labels,
    this.height = 190,
    this.barWidth = 16,
    this.labelInterval = 1,
  });

  final List<SeriesPoint> points;
  final List<String> labels;
  final double height;
  final double barWidth;
  final int labelInterval;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (points.isEmpty) return SizedBox(height: height);

    final double maxY = points
        .map((SeriesPoint p) => p.value)
        .reduce((double a, double b) => a > b ? a : b);
    final double top = maxY * 1.15;
    final double interval = top / 3;

    return SizedBox(
      height: height,
      child: _ChartGrow(
        builder: (double t) => BarChart(
          BarChartData(
            maxY: top == 0 ? 1 : top,
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: interval == 0 ? 1 : interval,
              getDrawingHorizontalLine: (double value) => FlLine(
                color: palette.border,
                strokeWidth: 1,
                dashArray: <int>[5, 5],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  interval: interval == 0 ? 1 : interval,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    if (value < interval * 0.5) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        Fmt.compact(value),
                        style: context.texts.labelSmall?.copyWith(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final int i = value.round();
                    if (i < 0 || i >= labels.length || i % labelInterval != 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        labels[i],
                        style: context.texts.labelSmall?.copyWith(
                          fontSize: 10.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (BarChartGroupData group) =>
                    context.isDark ? AppColors.mutedDark : AppColors.textLight,
                tooltipBorderRadius: BorderRadius.circular(10),
                getTooltipItem:
                    (
                      BarChartGroupData group,
                      int groupIndex,
                      BarChartRodData rod,
                      int rodIndex,
                    ) {
                      return BarTooltipItem(
                        Fmt.money(points[groupIndex].value),
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      );
                    },
              ),
            ),
            barGroups: List<BarChartGroupData>.generate(points.length, (int i) {
              return BarChartGroupData(
                x: i,
                barRods: <BarChartRodData>[
                  BarChartRodData(
                    toY: points[i].value * t,
                    width: barWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: <Color>[AppColors.primary, AppColors.secondary],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Donut with a legend — category and payment breakdowns.
class DonutBreakdown extends StatelessWidget {
  const DonutBreakdown({
    super.key,
    required this.slices,
    this.size = 132,
    this.centerLabel,
    this.centerValue,
    this.formatValue,
  });

  final List<BreakdownSlice> slices;
  final double size;
  final String? centerLabel;
  final String? centerValue;

  /// When provided, the legend shows a formatted amount instead of a percent.
  final String Function(double)? formatValue;

  @override
  Widget build(BuildContext context) {
    final AppPalette palette = context.palette;
    if (slices.isEmpty) return const SizedBox.shrink();

    final double total = slices.fold<double>(
      0,
      (double s, BreakdownSlice x) => s + x.value,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              _ChartGrow(
                builder: (double t) => PieChart(
                  PieChartData(
                    startDegreeOffset: -90 + (1 - t) * 90,
                    sectionsSpace: 3,
                    centerSpaceRadius: size * 0.30,
                    sections: slices.map((BreakdownSlice s) {
                      return PieChartSectionData(
                        value: s.value,
                        color: s.color.withValues(alpha: t),
                        radius: size * 0.19 * (0.6 + 0.4 * t),
                        showTitle: false,
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (centerValue != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      centerValue!,
                      style: context.texts.titleMedium?.copyWith(fontSize: 14),
                    ),
                    if (centerLabel != null)
                      Text(
                        centerLabel!,
                        style: context.texts.labelSmall?.copyWith(fontSize: 10),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: slices.map((BreakdownSlice s) {
              final double pct = total == 0 ? 0 : (s.value / total) * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: s.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.texts.bodyMedium?.copyWith(
                          color: palette.text,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      formatValue?.call(s.value) ??
                          '${pct.toStringAsFixed(0)}%',
                      style: context.texts.titleSmall?.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// Horizontal progress row — "Sales by Waiter", "Revenue by Category".
class BreakdownBars extends StatelessWidget {
  const BreakdownBars({
    super.key,
    required this.slices,
    required this.formatValue,
  });

  final List<BreakdownSlice> slices;
  final String Function(double) formatValue;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();
    final double max = slices
        .map((BreakdownSlice s) => s.value)
        .reduce((double a, double b) => a > b ? a : b);

    return Column(
      children: slices.map((BreakdownSlice s) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      s.label,
                      style: context.texts.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatValue(s.value),
                    style: context.texts.titleSmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: max == 0 ? 0 : s.value / max,
                ),
                duration: AppMotion.chart,
                curve: Curves.easeOutCubic,
                builder: (BuildContext context, double v, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: v,
                      minHeight: 7,
                      backgroundColor: context.palette.muted,
                      valueColor: AlwaysStoppedAnimation<Color>(s.color),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
