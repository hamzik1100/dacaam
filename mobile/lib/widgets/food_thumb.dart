import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Product imagery with a branded fallback.
///
/// Real photography arrives from the API in Phase 2. Until then — and whenever
/// a device is offline or an image 404s — this degrades to a tinted gradient
/// tile with the item's emoji, which keeps the POS grid looking deliberate
/// instead of broken.
class FoodThumb extends StatelessWidget {
  const FoodThumb({
    super.key,
    required this.emoji,
    this.imageUrl,
    this.size,
    this.radius = 12,
    this.tint = AppColors.primary,
    this.emojiScale = 0.46,
  });

  final String emoji;
  final String? imageUrl;

  /// `null` fills the available space (used by the POS grid).
  final double? size;
  final double radius;
  final Color tint;
  final double emojiScale;

  @override
  Widget build(BuildContext context) {
    final Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: imageUrl == null
          ? _fallback(context)
          : Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Decoded at roughly the size it is drawn at, not the size it
              // was uploaded at. An 800px photograph rendered into a 96pt
              // thumbnail otherwise costs about 2.5 MB of memory per card, and
              // a POS grid holds a dozen of them on screen at once.
              cacheWidth: size == null ? 400 : (size! * 3).round(),
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) =>
                      _fallback(context),
              loadingBuilder:
                  (
                    BuildContext context,
                    Widget child,
                    ImageChunkEvent? progress,
                  ) {
                    if (progress == null) return child;
                    return _fallback(context);
                  },
            ),
    );

    if (size == null) return content;
    return SizedBox(width: size, height: size, child: content);
  }

  Widget _fallback(BuildContext context) {
    final bool dark = context.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tint.withValues(alpha: dark ? 0.30 : 0.18),
            tint.withValues(alpha: dark ? 0.14 : 0.07),
          ],
        ),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: EdgeInsets.all((size ?? 60) * 0.18),
            child: Text(
              emoji,
              style: TextStyle(fontSize: (size ?? 72) * emojiScale),
            ),
          ),
        ),
      ),
    );
  }
}
