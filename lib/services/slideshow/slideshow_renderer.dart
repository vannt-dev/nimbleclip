import 'slideshow_renderer_stub.dart'
    if (dart.library.html) 'slideshow_renderer_stub.dart'
    as impl;

export 'slideshow_failure.dart';

/// The outcome of a successful slideshow render.
class SlideshowResult {
  const SlideshowResult({required this.filePath, required this.audioSkipped});

  /// Path to the rendered MP4 on disk.
  final String filePath;

  /// True when the render succeeded but the music track could not be
  /// transcoded, so the video was produced silent instead of failing.
  final bool audioSkipped;
}

/// Renders a TikTok photo post's images (and optional music) into one MP4.
///
/// Implementations are platform-specific and selected via conditional
/// import; see `createSlideshowRenderer`.
abstract interface class SlideshowRenderer {
  /// Whether this platform can actually render a slideshow.
  bool get isSupported;

  /// Renders [imagePaths] (in order) into an MP4 at [outputPath], showing
  /// each image for [perImage] and encoding at [width]x[height]. When
  /// [audioPath] is provided the renderer attempts to mux it in as the
  /// soundtrack.
  ///
  /// Throws a [SlideshowException] on failure.
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
  });
}

/// Creates the renderer for the current platform.
SlideshowRenderer createSlideshowRenderer() => impl.createSlideshowRenderer();
