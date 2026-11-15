import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/app_strings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/update/app_update.dart';
import '../../widgets/buttons.dart';

/// Shown instead of the app when the platform no longer supports this build.
///
/// Nothing behind it is touched — no session is ended and nothing is deleted.
/// Installing the new APK over this one keeps the sign-in, so the restaurant
/// is back where it was the moment the update lands.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.info,
    required this.onRecheck,
  });

  final UpdateInfo info;

  /// Asks the server again — for when the minimum was set by mistake and has
  /// since been lowered, so nobody has to reinstall to get past this.
  final Future<void> Function() onRecheck;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _checking = false;

  Future<void> _download() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = context.t('cannotOpen');
    final String url = widget.info.downloadUrl;

    try {
      if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        return;
      }
    } on PlatformException {
      // Falls through to the copy below.
    } on FormatException {
      // Likewise.
    }

    // No browser answered. The link on the clipboard can still be pasted into
    // one, or sent to whoever looks after the phones.
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(SnackBar(content: Text('$failed — $url')));
  }

  Future<void> _recheck() async {
    setState(() => _checking = true);
    await widget.onRecheck();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final UpdateInfo info = widget.info;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.brand,
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  context.t('updateRequiredTitle'),
                  textAlign: TextAlign.center,
                  style: context.texts.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  info.message.isNotEmpty
                      ? info.message
                      : context.t('updateRequiredBody'),
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.tp('updateVersions', <String, String>{
                    'current': AppConfig.appVersion,
                    'required': info.minVersion,
                  }),
                  textAlign: TextAlign.center,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.palette.subtext,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                GradientButton(
                  label: context.t('updateDownload'),
                  icon: Icons.download_rounded,
                  onPressed: info.downloadUrl.isEmpty ? null : _download,
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: _checking ? null : _recheck,
                  child: Text(context.t('updateCheckAgain')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
