// `dart.library.io` is the only usable discriminator here, and it covers iOS
// and desktop as well as Android. Selecting the native file for all of them is
// deliberate: the runtime `Platform.isAndroid` gate inside it is what actually
// narrows support, and it is the only thing that can.
import 'slideshow_renderer_stub.dart'
    if (dart.library.io) 'slideshow_renderer_android.dart'
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
  /// [onProgress] is called with a fraction from 0 to 1 as the encode
  /// advances. [renderId] names this render so [cancel] can address it; both
  /// are optional so a caller that wants neither can leave them out.
  ///
  /// Throws a [SlideshowException] on failure.
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
    String? renderId,
    void Function(double progress)? onProgress,
  });

  /// Asks the render started under [renderId] to stop.
  ///
  /// The in-flight [render] future then completes with a
  /// [SlideshowFailureKind.cancelled] exception. Cancelling an id that is not
  /// running is a no-op, not an error: the render may have finished between
  /// the user's tap and this call.
  Future<void> cancel(String renderId);
}

/// Creates the renderer for the current platform.
SlideshowRenderer createSlideshowRenderer() => impl.createSlideshowRenderer();
