import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/platform_style.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_cache_size.dart';
import '../../../models/video_metadata.dart';

/// Preview image for a result, with the platform badge, duration and the
/// control that opens the full preview.
///
/// Split out of `VideoResultCard` so that changing the selected quality or
/// ticking an image no longer rebuilds this subtree — the network image in it
/// is the most expensive part of the card.
class ResultThumbnailHeader extends StatelessWidget {
  const ResultThumbnailHeader({
    super.key,
    required this.metadata,
    required this.previewUrl,
    required this.isImagePreview,
    required this.onPreview,
  });

  final VideoMetadata metadata;

  /// The image to show. The header renders nothing when this is empty.
  final String previewUrl;

  /// Picks the magnifier over the play triangle for a still image.
  final bool isImagePreview;

  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    if (previewUrl.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(
            builder: (context, constraints) => CachedNetworkImage(
              imageUrl: previewUrl,
              fit: BoxFit.cover,
              memCacheWidth: imageCacheWidth(context, constraints.maxWidth),
              placeholder: (context, url) => Container(
                color: isDark ? AppColors.darkCardElevated : Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: isDark ? AppColors.darkCardElevated : Colors.grey[200],
                child: Icon(
                  metadata.platform.icon,
                  size: 48,
                  color: metadata.platform.brandColor,
                ),
              ),
            ),
          ),
        ),
        // Gradient overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(20),
                  Colors.black.withAlpha(120),
                ],
              ),
            ),
          ),
        ),
        // Play button to preview
        InkWell(
          onTap: onPreview,
          borderRadius: BorderRadius.circular(32),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(140),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: Icon(
              isImagePreview ? Icons.zoom_in_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        // Platform Badge
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: metadata.platform.brandColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 6),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(metadata.platform.icon, size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  metadata.platform.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Duration Pill
        if (metadata.duration != null)
          Positioned(
            bottom: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                Formatters.formatDuration(metadata.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
