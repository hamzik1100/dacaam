import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_redux/flutter_redux.dart';
import 'package:redux/redux.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../redux/app_state.dart';
import '../../widgets/app_card.dart';

/// Who to contact when the restaurant is mid-service and something is wrong.
///
/// Every row both launches and copies: a phone with no dialler, no mail client
/// or no WhatsApp still has to be able to hand the number to somebody, and a
/// support screen that does nothing when tapped is worse than a printed card.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const String _phone = '252634823102';
  static const String _email = 'info.hamzik@gmail.com';
  static const String _company = 'Kafiican Innovations';

  @override
  Widget build(BuildContext context) {
    return StoreConnector<AppState, _SupportVm>(
      converter: _SupportVm.from,
      builder: (BuildContext context, _SupportVm vm) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('helpSupport'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: <Widget>[
              _header(context),
              const SizedBox(height: AppSpacing.lg),

              AppCard(
                child: Column(
                  children: <Widget>[
                    _ContactRow(
                      icon: Icons.phone_rounded,
                      color: AppColors.success,
                      label: context.t('callUs'),
                      value: '+$_phone',
                      uri: Uri.parse('tel:+$_phone'),
                      copyText: '+$_phone',
                    ),
                    const _Divider(),
                    _ContactRow(
                      icon: Icons.chat_rounded,
                      color: AppColors.success,
                      label: 'WhatsApp',
                      value: '+$_phone',
                      uri: Uri.parse('https://wa.me/$_phone'),
                      copyText: '+$_phone',
                      external: true,
                    ),
                    const _Divider(),
                    _ContactRow(
                      icon: Icons.mail_outline_rounded,
                      color: AppColors.info,
                      label: context.t('emailUs'),
                      value: _email,
                      uri: Uri(
                        scheme: 'mailto',
                        path: _email,
                        query: _mailQuery(vm),
                      ),
                      copyText: _email,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Pre-filled into the email, and shown here so it can be read out
              // over the phone: support's first question is always which
              // restaurant, and staff rarely know the code by heart.
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      context.t('whenReporting'),
                      style: context.texts.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(label: 'Restaurant', value: vm.restaurantName),
                    _InfoRow(label: 'Code', value: vm.slug),
                    _InfoRow(label: context.t('name'), value: vm.userName),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              Center(
                child: Text(
                  _company,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[AppColors.primary, AppColors.secondary],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: const Icon(
            Icons.support_agent_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(_company, style: context.texts.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.t('supportIntro'),
          textAlign: TextAlign.center,
          style: context.texts.bodySmall?.copyWith(
            color: context.palette.subtext,
          ),
        ),
      ],
    );
  }

  static String _mailQuery(_SupportVm vm) {
    final String subject = Uri.encodeComponent('DACAAM · ${vm.slug}');
    final String body = Uri.encodeComponent(
      'Restaurant: ${vm.restaurantName} (${vm.slug})\n'
      'User: ${vm.userName}\n\n',
    );

    return 'subject=$subject&body=$body';
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.uri,
    required this.copyText,
    this.external = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Uri uri;
  final String copyText;

  /// WhatsApp is a web link that must leave the app rather than open in a
  /// webview, where it would show the "continue to chat" page and stall.
  final bool external;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      onLongPress: () => _copy(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.palette.subtext,
                    ),
                  ),
                  Text(value, style: context.texts.titleSmall),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 17),
              tooltip: context.t('copy'),
              onPressed: () => _copy(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = context.t('cannotOpen');

    try {
      final bool launched = await launchUrl(
        uri,
        mode: external
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      );
      if (launched) return;
    } on PlatformException {
      // Falls through to the copy below.
    }

    await Clipboard.setData(ClipboardData(text: copyText));
    messenger.showSnackBar(SnackBar(content: Text('$failed — $copyText')));
  }

  Future<void> _copy(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String copied = context.t('copied');

    await Clipboard.setData(ClipboardData(text: copyText));
    messenger.showSnackBar(SnackBar(content: Text('$copied: $copyText')));
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: context.texts.bodySmall?.copyWith(
                color: context.palette.subtext,
              ),
            ),
          ),
          Text(value, style: context.texts.bodyMedium),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: context.palette.border);
}

class _SupportVm {
  const _SupportVm({
    required this.restaurantName,
    required this.slug,
    required this.userName,
  });

  factory _SupportVm.from(Store<AppState> store) {
    final AppState s = store.state;

    return _SupportVm(
      restaurantName: s.restaurant.restaurant?.name ?? '—',
      slug: s.restaurant.restaurant?.slug ?? '—',
      userName: s.auth.user?.name ?? '—',
    );
  }

  final String restaurantName;
  final String slug;
  final String userName;
}
