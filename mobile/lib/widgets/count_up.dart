import 'package:flutter/material.dart';

/// Counts a number up on first paint and animates between values afterwards.
///
/// Used for KPI figures only — animating every number on screen would be
/// noise. [format] keeps currency/compact rules in the caller.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutCubic,
    this.maxLines = 1,
  });

  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: curve,
      builder: (BuildContext context, double v, Widget? child) {
        return Text(
          format(v),
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
