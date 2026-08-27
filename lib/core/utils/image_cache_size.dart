import 'package:flutter/widgets.dart';

/// Caps how much decoded image data Flutter keeps alive.
///
/// The framework defaults to 100 MB and 1000 entries. Those defaults suit an
/// app showing a handful of small images; NimbleClip renders grids of full-size
/// post photos, where 100 MB of decoded bitmaps is a large share of the heap on
/// a low-RAM Android device. The cache still holds far more than one screenful
/// at 48 MB, and evicting sooner costs a re-decode rather than a re-download —
/// `cached_network_image` keeps the bytes on disk either way.
void configureImageCacheBudget() {
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 200;
}

/// Converts a widget's logical width to the physical-pixel width expected by
/// image cache resizing APIs.
int imageCacheWidth(BuildContext context, double logicalWidth) {
  final width = (logicalWidth * MediaQuery.devicePixelRatioOf(context)).ceil();
  return width < 1 ? 1 : width;
}

/// Extra resolution kept so an `InteractiveViewer` still has detail to show
/// when the reader zooms in.
const double _previewZoomHeadroom = 2;

/// Ceiling on a preview decode, in physical pixels.
///
/// A full-resolution post photo can be several thousand pixels wide, and a
/// decoded bitmap costs four bytes per pixel: an uncapped 4000x3000 image is
/// about 48 MB of RAM for one preview. 4096 keeps a sharp image on every
/// current phone and tablet while bounding that cost.
const int _maximumPreviewWidth = 4096;

/// Decode width for a full-screen, zoomable image preview.
///
/// Sized from the screen rather than a fixed number so the preview stays sharp
/// on high-density displays, with headroom for zoom and a hard ceiling so a
/// very large source image cannot drive an unbounded decode.
int previewCacheWidth(BuildContext context) {
  final logicalWidth = MediaQuery.sizeOf(context).width;
  final width =
      (logicalWidth *
              MediaQuery.devicePixelRatioOf(context) *
              _previewZoomHeadroom)
          .ceil();
  if (width < 1) return 1;
  return width > _maximumPreviewWidth ? _maximumPreviewWidth : width;
}
