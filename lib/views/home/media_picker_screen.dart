import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/image_cache_size.dart';
import '../../core/utils/media_selection_helper.dart';
import '../../l10n/l10n.dart';
import '../../l10n/quality_descriptor_text.dart';
import '../../models/video_metadata.dart';
import '../player/video_player_screen.dart';
import 'widgets/media_preview_dialog.dart';

/// A lazy, full-screen chooser for a post that carries several media.
///
/// Serves photos and videos alike: a highlight can hold a dozen videos, and
/// picking between them from a list of names is guesswork. Keeping the grid
/// outside the home page avoids eagerly decoding every thumbnail inside its
/// parent scroll view; only visible cells are built and cached.
class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({
    super.key,
    required this.options,
    required this.initiallySelectedIds,
    required this.title,
  });

  final List<VideoQualityOption> options;

  /// Keyed the way the caller checks them: a photo by its own id, a video by
  /// the id it shares with its other qualities.
  final Set<String> initiallySelectedIds;

  final String title;

  /// A photo is its own entry; every quality of one video is a single entry.
  static String keyOf(VideoQualityOption option) =>
      option.isImage ? option.id : MediaSelectionHelper.videoKeyOf(option);

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  late final Set<String> _selectedIds = {...widget.initiallySelectedIds};

  void _toggle(VideoQualityOption option) {
    final key = MediaPickerScreen.keyOf(option);
    setState(() {
      if (!_selectedIds.add(key)) _selectedIds.remove(key);
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == widget.options.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(widget.options.map(MediaPickerScreen.keyOf));
      }
    });
  }

  /// A photo opens in the lightweight dialog; a video needs a real player, or
  /// the reader is choosing between still frames that all look alike.
  void _preview(VideoQualityOption option) {
    if (option.isImage) {
      unawaited(MediaPreviewDialog.show(context, option));
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            title: describeQuality(option.label, context.l10n),
            videoUrl: option.downloadUrl,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.options.map(MediaPickerScreen.keyOf).toSet();
    final allSelected = _selectedIds.length == keys.length;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900
        ? 5
        : width >= 600
        ? 4
        : 3;
    // Matches the grid delegate below: full width minus the outer padding and
    // the gaps between columns.
    const horizontalPadding = 12.0 * 2;
    const crossAxisSpacing = 8.0;
    final cellWidth =
        (width - horizontalPadding - crossAxisSpacing * (columns - 1)) /
        columns;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _toggleAll,
            child: Text(
              allSelected ? context.l10n.deselectAll : context.l10n.selectAll,
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemCount: widget.options.length,
        itemBuilder: (context, index) {
          final option = widget.options[index];
          final selected = _selectedIds.contains(
            MediaPickerScreen.keyOf(option),
          );
          return Semantics(
            label: describeQuality(option.label, context.l10n),
            selected: selected,
            button: true,
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _toggle(option),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: option.thumbnailUrl ?? option.downloadUrl,
                      httpHeaders: option.headers,
                      fit: BoxFit.cover,
                      // Sized from the real cell width rather than a fixed 360,
                      // which was blurry on high-density displays and wasteful
                      // on low-density ones.
                      memCacheWidth: imageCacheWidth(context, cellWidth),
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (_, _, _) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? AppColors.primary : Colors.white,
                        shadows: const [Shadow(blurRadius: 5)],
                      ),
                    ),
                    Positioned(
                      top: 2,
                      left: 2,
                      child: IconButton(
                        tooltip: context.l10n.preview,
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _preview(option),
                        icon: Icon(
                          option.isImage
                              ? Icons.zoom_in_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: Text(
                        describeQuality(option.label, context.l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 5)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: () => Navigator.pop(context, _selectedIds),
          icon: const Icon(Icons.check_rounded),
          label: Text('${widget.title} (${_selectedIds.length})'),
        ),
      ),
    );
  }
}
