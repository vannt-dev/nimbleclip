import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/image_cache_size.dart';
import '../../../models/video_metadata.dart';

/// Full-screen, zoomable look at the photos of a post, swiped between.
///
/// One widget for both entry points — the result card's preview button and the
/// carousel picker's magnifier. They had drifted into two near-identical
/// copies, which is how the missing `httpHeaders` bug came to need fixing in
/// two places at once.
///
/// Carries the whole set rather than one photo: looking at the next one used to
/// mean closing this and tapping that, which is a poor way to compare two
/// pictures of the same moment.
class MediaPreviewDialog extends StatefulWidget {
  const MediaPreviewDialog({
    super.key,
    required this.options,
    this.initialIndex = 0,
  });

  final List<VideoQualityOption> options;
  final int initialIndex;

  /// Opens the preview over [context], starting on [initialIndex] of [options].
  static Future<void> show(
    BuildContext context,
    List<VideoQualityOption> options, {
    int initialIndex = 0,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          MediaPreviewDialog(options: options, initialIndex: initialIndex),
    );
  }

  @override
  State<MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<MediaPreviewDialog> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(
      0,
      widget.options.isEmpty ? 0 : widget.options.length - 1,
    );
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: options.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (_, index) => _PreviewImage(option: options[index]),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          // Only worth showing when there is somewhere to swipe to. A count
          // reads better than dots here: an album can run to a dozen or more.
          if (options.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      '${_index + 1} / ${options.length}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.option});

  final VideoQualityOption option;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 4,
      child: CachedNetworkImage(
        imageUrl: option.downloadUrl,
        // Instagram and Facebook CDNs reject image requests that arrive
        // without the Referer the extractor collected, so the preview has
        // to send what the download sends.
        httpHeaders: option.headers,
        fit: BoxFit.contain,
        memCacheWidth: previewCacheWidth(context),
        placeholder: (_, _) => const SizedBox(
          height: 320,
          child: Center(child: CircularProgressIndicator()),
        ),
        errorWidget: (_, _, _) => const SizedBox(
          height: 240,
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}
