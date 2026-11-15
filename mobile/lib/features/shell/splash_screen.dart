import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

/// Brand splash shown until the first data load resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutBack,
              builder: (BuildContext context, double scale, Widget? child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: AppColors.brand,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: AppShadows.brand(),
                ),
                child: const Center(
                  child: Text('🍔', style: TextStyle(fontSize: 40)),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'DACAAM',
              style: context.texts.headlineMedium?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Restaurant POS & Management', style: context.texts.bodySmall),
            const SizedBox(height: AppSpacing.xxxl),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ],
        ),
      ),
    );
  }
}
