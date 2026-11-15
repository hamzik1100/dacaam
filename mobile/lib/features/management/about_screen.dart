import 'package:flutter/material.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../redux/app_state.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _AboutVm>(
      converter: _AboutVm.from,
      builder: (BuildContext context, _AboutVm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('aboutApp'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: <Widget>[
              Center(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: AppColors.brand,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: AppShadows.brand(),
                      ),
                      child: const Center(
                        child: Text('🍔', style: TextStyle(fontSize: 34)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'DACAAM POS',
                      style: context.texts.headlineSmall?.copyWith(
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Restaurant POS & Management',
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              AppCard(
                child: Column(
                  children: <Widget>[
                    DetailRow(
                      label: context.t('version'),
                      value: '1.0.0 (Phase 1)',
                      icon: Icons.tag_rounded,
                    ),
                    DetailRow(
                      label: context.t('name'),
                      value: vm.restaurantName,
                      icon: Icons.storefront_rounded,
                    ),
                    DetailRow(
                      label: 'Restaurant Code',
                      value: vm.slug,
                      icon: Icons.qr_code_rounded,
                    ),
                    DetailRow(
                      label: 'Tenant ID',
                      value: '${vm.restaurantId}',
                      icon: Icons.fingerprint_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SectionHeader(title: context.t('system')),
                    Text(
                      'Flutter mobile client · Redux state · REST API · PHP · MySQL',
                      style: context.texts.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Data for this restaurant is isolated by restaurant_id. '
                      'The mobile client never talks to the database directly.',
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AboutVm {
  const _AboutVm({
    required this.restaurantName,
    required this.slug,
    required this.restaurantId,
  });

  factory _AboutVm.from(Store<AppState> store) {
    final AppState s = store.state;
    return _AboutVm(
      restaurantName: s.restaurant.restaurant?.name ?? '',
      slug: s.restaurant.restaurant?.slug ?? '',
      restaurantId: s.restaurant.restaurant?.id ?? 0,
    );
  }

  final String restaurantName;
  final String slug;
  final int restaurantId;
}
