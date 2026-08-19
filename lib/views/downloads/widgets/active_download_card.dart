import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/download_task.dart';

class ActiveDownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onCancel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const ActiveDownloadCard({
    super.key,
    required this.task,
    required this.onCancel,
    this.onPause,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final percent = (task.progress * 100).toInt();
    final isPaused = task.status == DownloadStatus.paused;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: task.thumbnailUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: task.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(
                            color: task.platform.brandColor.withAlpha(30),
                            child: Icon(
                              task.platform.icon,
                              color: task.platform.brandColor,
                            ),
                          ),
                        )
                      : Container(
                          color: task.platform.brandColor.withAlpha(30),
                          child: Icon(
                            task.platform.icon,
                            color: task.platform.brandColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Title and Platform
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          task.platform.icon,
                          size: 13,
                          color: task.platform.brandColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.qualityLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Pause / resume — only offered where a partial file can be kept.
              if (isPaused && onResume != null)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  color: AppColors.success,
                  onPressed: onResume,
                  tooltip: context.l10n.resumeDownload,
                )
              else if (!isPaused && onPause != null)
                IconButton(
                  icon: const Icon(Icons.pause_rounded, size: 22),
                  color: AppColors.warning,
                  onPressed: task.status == DownloadStatus.downloading
                      ? onPause
                      : null,
                  tooltip: context.l10n.pauseDownload,
                ),

              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: Colors.redAccent,
                onPressed: onCancel,
                tooltip: context.l10n.cancelDownload,
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress Bar — a paused bar holds its position instead of animating.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (task.progress > 0 || isPaused) ? task.progress : null,
              minHeight: 6,
              backgroundColor: isDark
                  ? AppColors.darkCardElevated
                  : AppColors.lightCardElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused ? AppColors.warning : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Progress stats & Speed
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Formatters.formatBytes(task.receivedBytes)} / ${task.totalBytes > 0 ? Formatters.formatBytes(task.totalBytes) : '--'} ($percent%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              Text(
                isPaused
                    ? context.l10n.paused
                    : Formatters.formatSpeed(task.downloadSpeed),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isPaused ? AppColors.warning : AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
