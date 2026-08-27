import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/image_cache_size.dart';
import '../../../models/video_metadata.dart';

/// Title, author and engagement counts for a result.
///
/// Nothing here depends on the selected quality or the image selection, so it
/// stays put while the reader picks their way through the options below it.
class ResultMetadataSummary extends StatelessWidget {
  const ResultMetadataSummary({super.key, required this.metadata});

  final VideoMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final avatarUrl = metadata.authorAvatar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          metadata.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (avatarUrl != null && avatarUrl.isNotEmpty) ...[
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: avatarUrl,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  memCacheWidth: imageCacheWidth(context, 22),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.person_rounded, size: 18),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                metadata.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondary,
                ),
              ),
            ),
            if (metadata.viewCount != null) ...[
              Icon(Icons.visibility_outlined, size: 14, color: secondary),
              const SizedBox(width: 4),
              Text(
                Formatters.formatCount(metadata.viewCount!),
                style: TextStyle(fontSize: 12, color: secondary),
              ),
              const SizedBox(width: 10),
            ],
            if (metadata.likeCount != null) ...[
              const Icon(
                Icons.favorite_rounded,
                size: 14,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 4),
              Text(
                Formatters.formatCount(metadata.likeCount!),
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
