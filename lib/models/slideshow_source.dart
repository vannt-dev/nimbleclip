/// What the device needs in order to render a photo post into one video.
///
/// Carries URLs rather than files: fetching belongs to the service layer,
/// which already owns the headers, the retry policy and the privacy switch.
class SlideshowSource {
  const SlideshowSource({
    required this.imageUrls,
    this.audioUrl,
    this.perImage = const Duration(seconds: 3),
    this.width = 1080,
    this.height = 1920,
  });

  final List<String> imageUrls;

  /// Null when the post carried no music, or when the track cannot be used.
  final String? audioUrl;

  final Duration perImage;
  final int width;
  final int height;

  Duration get totalDuration => perImage * imageUrls.length;
}
