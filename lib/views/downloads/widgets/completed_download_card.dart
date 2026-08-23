import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/download_task.dart';

class CompletedDownloadCard extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback onPlay;
  final VoidCallback onSaveGallery;
  final VoidCallback onShare;
  final VoidCallback onOpenExternal;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;

  const CompletedDownloadCard({
    super.key,
    required this.task,
    required this.onPlay,
    required this.onSaveGallery,
    required this.onShare,
    required this.onOpenExternal,
    required this.onDelete,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFailed =
        task.status == DownloadStatus.failed ||
        task.status == DownloadStatus.cancelled;

    final isCompleted = task.status == DownloadStatus.completed;
    final isHandedOff = task.status == DownloadStatus.handedOff;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFailed
              ? AppColors.error.withAlpha(80)
              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Thumbnail / Play Button
              InkWell(
                onTap: !isFailed && isCompleted ? onPlay : null,
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
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
                    if (!isFailed && isCompleted)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(150),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          task.isImage
                              ? Icons.visibility_outlined
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Title and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
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
                          task.isImage
                              ? Icons.image_outlined
                              : task.platform.icon,
                          size: 13,
                          color: task.isImage
                              ? AppColors.primary
                              : task.platform.brandColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          task.qualityLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• ${Formatters.formatBytes(task.totalBytes)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatDate(task.completedAt ?? task.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.darkTextSecondary.withAlpha(160)
                            : AppColors.lightTextSecondary.withAlpha(160),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isFailed) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      switch (task.errorMessage) {
                        'download_interrupted' =>
                          context.l10n.downloadInterrupted,
                        'local_file_missing' => context.l10n.localFileMissing,
                        _ => task.errorMessage ?? context.l10n.downloadFailed,
                      },
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n.retry,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          if (isHandedOff) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.info.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.download_done_rounded,
                    size: 16,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.browserDownloadStarted,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Actions Row
          Wrap(
            alignment: WrapAlignment.spaceAround,
            runAlignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: 4,
            children: [
              if (!isFailed && isCompleted) ...[
                _ActionButton(
                  icon: task.isImage
                      ? Icons.image_outlined
                      : Icons.play_circle_outline_rounded,
                  label: context.l10n.view,
                  color: AppColors.primary,
                  onTap: onPlay,
                ),
                if (!task.isAudioOnly)
                  _ActionButton(
                    icon: task.isSavedToGallery
                        ? Icons.check_circle_rounded
                        : Icons.photo_library_outlined,
                    label: task.isSavedToGallery
                        ? context.l10n.saved
                        : context.l10n.saveToGallery,
                    color: task.isSavedToGallery
                        ? AppColors.success
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                    onTap: onSaveGallery,
                  ),
                _ActionButton(
                  icon: Icons.share_outlined,
                  label: context.l10n.share,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  onTap: onShare,
                ),
                _ActionButton(
                  icon: Icons.open_in_new_rounded,
                  label: context.l10n.openWith,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                  onTap: onOpenExternal,
                ),
              ],
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: context.l10n.delete,
                color: AppColors.error,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
