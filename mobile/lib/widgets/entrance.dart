import 'package:flutter/material.dart';

import '../core/theme/app_dimens.dart';

/// Fade + rise entrance used for dashboard cards and list rows.
///
/// The stagger is capped: on a long list the delay stops growing after a few
/// rows so scrolled-in content never feels sluggish to staff.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.stagger = const Duration(milliseconds: 45),
    this.maxStaggerSteps = 8,
    this.offset = 16,
    this.duration = AppMotion.slow,
  });

  final Widget child;
  final int index;
  final Duration stagger;
  final int maxStaggerSteps;
  final double offset;
  final Duration duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();

    // The stagger is folded into the animation as a leading Interval rather
    // than a delayed Timer: a row that scrolls into view and is disposed a
    // frame later must not leave a pending timer behind.
    final int steps = widget.index.clamp(0, widget.maxStaggerSteps);
    final Duration delay = widget.stagger * steps;
    final Duration total = delay + widget.duration;

    _controller = AnimationController(vsync: this, duration: total);
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: AppMotion.enter,
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (BuildContext context, Widget? child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _curve.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Scales its child briefly when [trigger] changes — the cart badge bounce.
class BouncePulse extends StatefulWidget {
  const BouncePulse({super.key, required this.child, required this.trigger});

  final Widget child;
  final Object? trigger;

  @override
  State<BouncePulse> createState() => _BouncePulseState();
}

class _BouncePulseState extends State<BouncePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1, end: 1.28),
          weight: 45,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(begin: 1.28, end: 1),
          weight: 55,
        ),
      ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant BouncePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Press-to-shrink feedback for product cards and quick actions.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: AppMotion.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
