import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/enums.dart';
import '../../data/models/order.dart';
import '../../data/models/restaurant.dart';
import '../../redux/app_state.dart';
import '../orders/receipt.dart';
import '../../widgets/app_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common.dart';

/// Post-checkout confirmation: an animated tick, the receipt essentials, and
/// the one action staff actually want next — start the following order.
class OrderSuccessScreen extends StatefulWidget {
  const OrderSuccessScreen({super.key, required this.order});

  final RestaurantOrder order;

  @override
  State<OrderSuccessScreen> createState() => _OrderSuccessScreenState();
}

class _OrderSuccessScreenState extends State<OrderSuccessScreen>
    with TickerProviderStateMixin {
  // One controller drives both the tick and the content reveal; the content
  // simply starts a third of the way in via an Interval, which keeps the
  // sequencing on the ticker instead of a delayed callback.
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  late final Animation<double> _content = CurvedAnimation(
    parent: _tick,
    curve: const Interval(0.28, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _tick.forward();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final RestaurantOrder o = widget.order;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: SoftIconButton(
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const Spacer(),
              _AnimatedCheck(controller: _tick),
              const SizedBox(height: AppSpacing.xxl),
              FadeTransition(
                opacity: _content,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(_content),
                  child: Column(
                    children: <Widget>[
                      Text(
                        context.t('orderCompleted'),
                        style: context.texts.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        Fmt.orderNo(o.number),
                        style: context.texts.titleLarge?.copyWith(
                          color: context.palette.subtext,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        Fmt.money(o.total),
                        style: context.texts.displaySmall?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      AppCard(
                        child: Column(
                          children: <Widget>[
                            DetailRow(
                              label: context.t('orderTypeLabel'),
                              value: context.t(o.type.labelKey),
                              dense: true,
                            ),
                            if (o.tableLabel != null)
                              DetailRow(
                                label: context.t('table'),
                                value: o.tableLabel!,
                                dense: true,
                              ),
                            if (o.waiterName.isNotEmpty)
                              DetailRow(
                                label: context.t('waiter'),
                                value: o.waiterName,
                                dense: true,
                              ),
                            DetailRow(
                              label: context.t('items'),
                              value: '${o.itemCount}',
                              dense: true,
                            ),
                            if (o.primaryPayment != null)
                              DetailRow(
                                label: context.t('paymentMethod'),
                                value: o.primaryPayment!.label,
                                dense: true,
                              ),
                            // The order went through; the money may not have.
                            // Saying so here is the difference between a till
                            // that records a debt and one that hides it.
                            if (!o.paymentStatus.isSettled)
                              DetailRow(
                                label: context.t('payment'),
                                value: context.t(o.paymentStatus.labelKey),
                                valueColor: o.paymentStatus.color,
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FadeTransition(
                opacity: _content,
                child: Column(
                  children: <Widget>[
                    GradientButton(
                      label: context.t('startNewOrder'),
                      icon: Icons.add_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _receipt(context, share: false),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: Text(context.t('printReceipt')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 50),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // Most customers here would rather have it on their
                        // phone than on paper, and the restaurant saves a roll.
                        OutlinedButton(
                          onPressed: () => _receipt(context, share: true),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(56, 50),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.share_rounded, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the receipt and hands it to the printer or the share sheet.
  ///
  /// Failures are shown rather than swallowed: a print button that appears to
  /// do nothing sends staff hunting for a paper jam that is not there.
  Future<void> _receipt(BuildContext context, {required bool share}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Store<AppState> store = StoreProvider.of<AppState>(
      context,
      listen: false,
    );
    final Restaurant? restaurant = store.state.restaurant.restaurant;
    final AppLanguage lang = store.state.settings.language;

    if (restaurant == null) return;

    try {
      if (share) {
        await Receipt.share(widget.order, restaurant, lang);
      } else {
        await Receipt.print(widget.order, restaurant, lang);
      }
    } on Exception catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
      );
    }
  }
}

/// Scale-in medallion with a stroke-drawn tick.
class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final Animation<double> scale = CurvedAnimation(
      parent: controller,
      curve: const Interval(0, 0.34, curve: Curves.easeOutBack),
    );
    final Animation<double> stroke = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.22, 0.68, curve: Curves.easeOutCubic),
    );

    return ScaleTransition(
      scale: scale,
      child: Container(
        width: 108,
        height: 108,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success.withValues(alpha: 0.12),
        ),
        child: Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
            child: AnimatedBuilder(
              animation: stroke,
              builder: (BuildContext context, _) =>
                  CustomPaint(painter: _CheckPainter(progress: stroke.value)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final Offset a = Offset(size.width * 0.28, size.height * 0.52);
    final Offset b = Offset(size.width * 0.44, size.height * 0.67);
    final Offset c = Offset(size.width * 0.73, size.height * 0.36);

    // Two segments drawn in sequence: the short down-stroke, then the long up.
    const double firstLegShare = 0.38;
    final Path path = Path()..moveTo(a.dx, a.dy);
    if (progress <= firstLegShare) {
      final double t = progress / firstLegShare;
      path.lineTo(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    } else {
      final double t = (progress - firstLegShare) / (1 - firstLegShare);
      path.lineTo(b.dx, b.dy);
      path.lineTo(b.dx + (c.dx - b.dx) * t, b.dy + (c.dy - b.dy) * t);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
