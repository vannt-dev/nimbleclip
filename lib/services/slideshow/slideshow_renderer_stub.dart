import 'slideshow_renderer.dart';

/// Fallback renderer for platforms with no encoder implementation.
///
/// Currently used on every platform; Task 10 adds an Android implementation
/// and swaps the conditional export in `slideshow_renderer.dart` to select
/// it, without needing to change this file.
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
