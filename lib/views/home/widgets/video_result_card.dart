import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../l10n/l10n.dart';
import '../../../models/video_metadata.dart';
import '../image_picker_screen.dart';

class VideoResultCard extends StatefulWidget {
  final VideoMetadata metadata;
  final VideoQualityOption? selectedQuality;
  final Function(VideoQualityOption quality) onQualitySelected;
  final ValueChanged<List<VideoQualityOption>> onDownload;
  final VoidCallback onPreview;

  const VideoResultCard({
    super.key,
    required this.metadata,
    required this.selectedQuality,
    required this.onQualitySelected,
    required this.onDownload,
    required this.onPreview,
  });

  @override
  State<VideoResultCard> createState() => _VideoResultCardState();
}

class _VideoResultCardState extends State<VideoResultCard> {
  int _selectedTab = 0; // 0 = Video, 1 = Audio
  final Set<String> _selectedImageIds = {};

  List<VideoQualityOption> get _imageOptions =>
      widget.metadata.qualities.where((option) => option.isImage).toList();

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.selectedQuality?.isAudioOnly == true ? 1 : 0;
    _selectAllImages();
  }

  @override
  void didUpdateWidget(covariant VideoResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id ||
        oldWidget.metadata.originalUrl != widget.metadata.originalUrl) {
      _selectAllImages();
      _selectedTab = widget.selectedQuality?.isAudioOnly == true ? 1 : 0;
    }
  }

  void _selectAllImages() {
    _selectedImageIds
      ..clear()
      ..addAll(_imageOptions.map((option) => option.id));
  }

  Future<void> _openImagePicker(List<VideoQualityOption> options) async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => ImagePickerScreen(
          options: options,
          initiallySelectedIds: _selectedImageIds,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedImageIds
        ..clear()
        ..addAll(selected);
    });
    final first = options
        .where((option) => selected.contains(option.id))
        .firstOrNull;
    if (first != null) widget.onQualitySelected(first);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = widget.metadata;

    final videoOptions = meta.qualities
        .where((q) => !q.isAudioOnly && !q.isImage)
        .toList();
    final imageOptions = _imageOptions;
    final audioOptions = meta.qualities.where((q) => q.isAudioOnly).toList();
    final currentOptions = _selectedTab == 0 ? videoOptions : audioOptions;
    final selectedImages = imageOptions
        .where(
          (option) => option.isImage && _selectedImageIds.contains(option.id),
        )
        .toList();
    final selectedDownloads = <VideoQualityOption>[];
    final selectedQuality = widget.selectedQuality;
    if (selectedQuality?.isAudioOnly == true) {
      selectedDownloads.add(selectedQuality!);
    } else {
      final videoGroups = <String, List<VideoQualityOption>>{};
      for (final option in videoOptions) {
        (videoGroups[option.mediaId ?? 'primary-video'] ??= []).add(option);
      }
      for (final group in videoGroups.values) {
        selectedDownloads.add(
          group.any((option) => option.id == selectedQuality?.id)
              ? selectedQuality!
              : group.first,
        );
      }
      selectedDownloads.addAll(selectedImages);
    }
    final previewUrl = widget.selectedQuality?.isImage == true
        ? widget.selectedQuality!.downloadUrl
        : meta.coverUrl;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withAlpha(60)
                : Colors.black.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Thumbnail Header with Duration & Play overlay
          if (previewUrl.isNotEmpty)
            Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: previewUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: isDark
                          ? AppColors.darkCardElevated
                          : Colors.grey[200],
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: isDark
                          ? AppColors.darkCardElevated
                          : Colors.grey[200],
                      child: Icon(
                        meta.platform.icon,
                        size: 48,
                        color: meta.platform.brandColor,
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
                  onTap: widget.onPreview,
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                    child: Icon(
                      widget.selectedQuality?.isImage == true
                          ? Icons.zoom_in_rounded
                          : Icons.play_arrow_rounded,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: meta.platform.brandColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(60),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(meta.platform.icon, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          meta.platform.displayName,
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
                if (meta.duration != null)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        Formatters.formatDuration(meta.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

          // 2. Body Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Title
                Text(
                  meta.title,
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

                // Author & Engagement stats
                Row(
                  children: [
                    if (meta.authorAvatar != null &&
                        meta.authorAvatar!.isNotEmpty) ...[
                      ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: meta.authorAvatar!,
                          width: 22,
                          height: 22,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.person_rounded, size: 18),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        meta.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                    if (meta.viewCount != null) ...[
                      Icon(
                        Icons.visibility_outlined,
                        size: 14,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Formatters.formatCount(meta.viewCount!),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (meta.likeCount != null) ...[
                      const Icon(
                        Icons.favorite_rounded,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Formatters.formatCount(meta.likeCount!),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Video / Audio Mode Tabs
                if (audioOptions.isNotEmpty &&
                    (videoOptions.isNotEmpty || imageOptions.isNotEmpty))
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkCardElevated
                          : AppColors.lightCardElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedTab = 0);
                              if (videoOptions.isNotEmpty) {
                                widget.onQualitySelected(videoOptions.first);
                              } else if (imageOptions.isNotEmpty) {
                                widget.onQualitySelected(imageOptions.first);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                videoOptions.isNotEmpty
                                    ? context.l10n.videoOptions(
                                        videoOptions.length,
                                      )
                                    : context.l10n.imageOptions(
                                        imageOptions.length,
                                      ),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedTab == 0
                                      ? Colors.white
                                      : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() => _selectedTab = 1);
                              if (audioOptions.isNotEmpty) {
                                widget.onQualitySelected(audioOptions.first);
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                context.l10n.audioOptions(audioOptions.length),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 4. Quality Selector List
                if (currentOptions.isNotEmpty) ...[
                  Text(
                    context.l10n.selectDownloadQuality,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...currentOptions.map((opt) {
                    final isSelected = widget.selectedQuality?.id == opt.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => widget.onQualitySelected(opt),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withAlpha(isDark ? 40 : 25)
                                : (isDark
                                      ? AppColors.darkCardElevated.withAlpha(
                                          120,
                                        )
                                      : AppColors.lightCardElevated),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 18,
                                color: isSelected
                                    ? AppColors.primary
                                    : (isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  opt.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? (isDark
                                              ? Colors.white
                                              : AppColors.primaryDark)
                                        : (isDark
                                              ? AppColors.darkTextPrimary
                                              : AppColors.lightTextPrimary),
                                  ),
                                ),
                              ),
                              if (opt.sizeBytes != null && opt.sizeBytes! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.black26
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    Formatters.formatBytes(opt.sizeBytes!),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextSecondary
                                          : AppColors.lightTextSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                if (imageOptions.isNotEmpty && _selectedTab == 0) ...[
                  if (currentOptions.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.imageOptions(imageOptions.length),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_selectedImageIds.length ==
                                imageOptions.length) {
                              _selectedImageIds.clear();
                            } else {
                              _selectedImageIds
                                ..clear()
                                ..addAll(
                                  imageOptions.map((option) => option.id),
                                );
                            }
                          });
                        },
                        child: Text(
                          _selectedImageIds.length == imageOptions.length
                              ? context.l10n.deselectAll
                              : context.l10n.selectAll,
                        ),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openImagePicker(imageOptions),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      '${context.l10n.selectImages} '
                      '(${_selectedImageIds.length}/${imageOptions.length})',
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // 5. Actions: Preview & Download
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onPreview,
                      icon: Icon(
                        widget.selectedQuality?.isImage == true
                            ? Icons.image_outlined
                            : Icons.play_circle_outline_rounded,
                        size: 18,
                      ),
                      label: Text(context.l10n.preview),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: selectedDownloads.isEmpty
                            ? null
                            : () => widget.onDownload(selectedDownloads),
                        icon: const Icon(Icons.file_download_rounded, size: 20),
                        label: Text(
                          selectedDownloads.length > 1
                              ? context.l10n.downloadSelected(
                                  selectedDownloads.length,
                                )
                              : context.l10n.downloadNow,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
