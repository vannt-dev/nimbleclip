import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/media_selection_helper.dart';
import '../../../l10n/l10n.dart';
import '../../../models/video_metadata.dart';
import '../media_picker_screen.dart';
import 'result_media_tabs.dart';
import 'result_metadata_summary.dart';
import 'result_quality_list.dart';
import 'result_thumbnail_header.dart';

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
  final Set<String> _selectedVideoIds = {};

  List<VideoQualityOption> get _imageOptions =>
      widget.metadata.qualities.where((option) => option.isImage).toList();

  /// One entry per video, whatever qualities it is offered at.
  List<VideoQualityOption> get _videoEntries {
    final seen = <String>{};
    return [
      for (final option in widget.metadata.qualities)
        if (!option.isAudioOnly && !option.isImage)
          if (seen.add(MediaSelectionHelper.videoKeyOf(option))) option,
    ];
  }

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.selectedQuality?.isAudioOnly == true ? 1 : 0;
    _selectAllImages();
    _selectAllVideos();
  }

  @override
  void didUpdateWidget(covariant VideoResultCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.id != widget.metadata.id ||
        oldWidget.metadata.originalUrl != widget.metadata.originalUrl) {
      _selectAllImages();
      _selectAllVideos();
      _selectedTab = widget.selectedQuality?.isAudioOnly == true ? 1 : 0;
    }
  }

  void _selectAllImages() {
    _selectedImageIds
      ..clear()
      ..addAll(_imageOptions.map((option) => option.id));
  }

  /// Everything is checked to begin with, which is what the card downloaded
  /// before there was any way to uncheck.
  void _selectAllVideos() {
    _selectedVideoIds
      ..clear()
      ..addAll(_videoEntries.map(MediaSelectionHelper.videoKeyOf));
  }

  Future<void> _openImagePicker(List<VideoQualityOption> options) async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(
          options: options,
          initiallySelectedIds: _selectedImageIds,
          title: context.l10n.selectImages,
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

  Future<void> _openVideoPicker(List<VideoQualityOption> options) async {
    final selected = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => MediaPickerScreen(
          options: options,
          initiallySelectedIds: _selectedVideoIds,
          title: context.l10n.selectVideos,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedVideoIds
        ..clear()
        ..addAll(selected);
    });
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
    final videoEntries = _videoEntries;
    final selectedDownloads = MediaSelectionHelper.downloads(
      options: meta.qualities,
      selectedQuality: widget.selectedQuality,
      selectedImageIds: _selectedImageIds,
      selectedVideoIds: _selectedVideoIds,
    );
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
          ResultThumbnailHeader(
            metadata: meta,
            previewUrl: previewUrl,
            isImagePreview: widget.selectedQuality?.isImage == true,
            onPreview: widget.onPreview,
          ),

          // 2. Body Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResultMetadataSummary(metadata: meta),
                const SizedBox(height: 16),

                // 3. Video / Audio Mode Tabs
                ResultMediaTabs(
                  selectedTab: _selectedTab,
                  videoCount: videoOptions.length,
                  imageCount: imageOptions.length,
                  audioCount: audioOptions.length,
                  onVisualSelected: () {
                    setState(() => _selectedTab = 0);
                    if (videoOptions.isNotEmpty) {
                      widget.onQualitySelected(videoOptions.first);
                    } else if (imageOptions.isNotEmpty) {
                      widget.onQualitySelected(imageOptions.first);
                    }
                  },
                  onAudioSelected: () {
                    setState(() => _selectedTab = 1);
                    if (audioOptions.isNotEmpty) {
                      widget.onQualitySelected(audioOptions.first);
                    }
                  },
                ),

                // 4. Quality Selector List
                ResultQualityList(
                  // With several videos the reader is choosing between videos,
                  // not between qualities of one; the picker replaces the
                  // quality list rather than sitting beside it.
                  options: _selectedTab == 0 && videoEntries.length > 1
                      ? const []
                      : currentOptions,
                  selectedQualityId: widget.selectedQuality?.id,
                  onQualitySelected: widget.onQualitySelected,
                  videoEntries: _selectedTab == 0 && videoEntries.length > 1
                      ? videoEntries
                      : const [],
                  selectedVideoIds: _selectedVideoIds,
                  onToggleAllVideos: () {
                    setState(() {
                      if (_selectedVideoIds.length == videoEntries.length) {
                        _selectedVideoIds.clear();
                      } else {
                        _selectAllVideos();
                      }
                    });
                  },
                  onOpenVideoPicker: () => _openVideoPicker(videoEntries),
                  imageOptions: imageOptions,
                  selectedImageIds: _selectedImageIds,
                  showImageSelection:
                      imageOptions.isNotEmpty && _selectedTab == 0,
                  onToggleAllImages: () {
                    setState(() {
                      if (_selectedImageIds.length == imageOptions.length) {
                        _selectedImageIds.clear();
                      } else {
                        _selectAllImages();
                      }
                    });
                  },
                  onOpenPicker: () => _openImagePicker(imageOptions),
                ),

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
