import 'package:flutter/material.dart';

import '../../../core/theme/platform_style.dart';
import '../../../models/video_platform.dart';

class PlatformBadges extends StatelessWidget {
  final Function(VideoPlatform platform)? onPlatformTap;

  const PlatformBadges({super.key, this.onPlatformTap});

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
    ];

    // Wrapped rather than scrolled sideways: a row cut off at the screen edge
    // hid the platforms after the third, with nothing to say there were more.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: platforms.map((p) {
          return Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => onPlatformTap?.call(p),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? p.brandColor.withAlpha(35)
                      : p.brandColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: p.brandColor.withAlpha(isDark ? 80 : 60),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(p.icon, size: 18, color: p.brandColor),
                    const SizedBox(width: 6),
                    Text(
                      p.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
