import 'package:flutter/material.dart';
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
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: platforms.map((p) {
          return Padding(
            padding: const EdgeInsets.only(right: 10),
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
