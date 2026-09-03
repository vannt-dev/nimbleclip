import 'slideshow_renderer.dart';

/// Fallback renderer for platforms with no encoder implementation.
///
/// Selected on Web, which is the only place the conditional import in
/// `slideshow_renderer.dart` can exclude: `dart.library.io` is true on iOS and
/// desktop too, so those get `slideshow_renderer_android.dart` and are turned
/// away by its runtime `Platform.isAndroid` check rather than by this file.
class UnsupportedSlideshowRenderer implements SlideshowRenderer {
  const UnsupportedSlideshowRenderer();

  @override
  bool get isSupported => false;

  @override
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
  }) async {
    throw const SlideshowException(SlideshowFailureKind.encoderUnavailable);
  }
}

SlideshowRenderer createSlideshowRenderer() =>
    const UnsupportedSlideshowRenderer();
