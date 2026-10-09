import 'package:flutter/material.dart';

import '../../../core/theme/platform_style.dart';
import '../../../models/video_platform.dart';

class PlatformBadges extends StatelessWidget {
  final Function(VideoPlatform platform)? onPlatformTap;

  const PlatformBadges({super.key, this.onPlatformTap});

  static const double _spacing = 8;
  static const double _minSize = 28;
  static const double _maxSize = 40;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final platforms = [
      VideoPlatform.youtube,
      VideoPlatform.tiktok,
      VideoPlatform.facebook,
      VideoPlatform.twitter,
      VideoPlatform.instagram,
      VideoPlatform.threads,
      VideoPlatform.pinterest,
      VideoPlatform.soundcloud,
      VideoPlatform.flickr,
    ];

    // Icons only, sized to share one row: with their names beside them the
    // badges wrapped onto several rows and took a third of the screen. The
    // name is still the tooltip, the screen reader label and what a tap says.
    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = _spacing * (platforms.length - 1);
        final size = ((constraints.maxWidth - gaps) / platforms.length)
            .floorToDouble()
            .clamp(_minSize, _maxSize);

        // Wrapped rather than scrolled sideways: a row cut off at the screen
        // edge hides the platforms after it, with nothing to say there are
        // more. It only wraps on a screen too narrow for the smallest size.
        return SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: _spacing,
            runSpacing: _spacing,
            children: platforms.map((p) {
              return Tooltip(
                message: p.displayName,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onPlatformTap?.call(p),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark
                            ? p.brandColor.withAlpha(35)
                            : p.brandColor.withAlpha(20),
                        border: Border.all(
                          color: p.brandColor.withAlpha(isDark ? 80 : 60),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        p.icon,
                        size: size * 0.5,
                        color: p.brandColor,
                        semanticLabel: p.displayName,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
