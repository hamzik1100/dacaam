import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';

/// Shown instead of the app when a release build has no server behind it.
///
/// It exists because the alternative is worse than a crash. Without a server
/// the app falls back to the seeded dataset: the login screen accepts any
/// password, the dashboard shows invented takings, and every screen looks
/// exactly like the working one. Somebody could run a shift on it before
/// noticing the figures were never theirs.
///
/// Deliberately in English and unstyled by the app theme — it is aimed at
/// whoever built the APK, not at the restaurant, and it should be impossible
/// to mistake for part of the product.
class MisconfiguredScreen extends StatelessWidget {
  const MisconfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.danger,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 56,
                    color: Colors.white,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'This build has no server',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'It was compiled without USE_API, so it would run on demo '
                    'data and accept any password. Do not install it on a till.',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const Text(
                    'Rebuild with:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const SelectableText(
                    'BUILD.bat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SelectableText(
                    'USE_API=${AppConfig.useApi}\n'
                    'API_BASE_URL=${AppConfig.apiBaseUrl}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'monospace',
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
