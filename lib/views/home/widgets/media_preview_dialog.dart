import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/image_cache_size.dart';
import '../../../models/video_metadata.dart';

/// Full-screen, zoomable look at a single image option.
///
/// One widget for both entry points — the result card's preview button and the
/// carousel picker's magnifier. They had drifted into two near-identical
/// copies, which is how the missing `httpHeaders` bug came to need fixing in
/// two places at once.
class MediaPreviewDialog extends StatelessWidget {
  const MediaPreviewDialog({super.key, required this.option});

  final VideoQualityOption option;

  /// Opens the preview over [context].
  static Future<void> show(BuildContext context, VideoQualityOption option) {
    return showDialog<void>(
      context: context,
      builder: (_) => MediaPreviewDialog(option: option),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          InteractiveViewer(
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
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
