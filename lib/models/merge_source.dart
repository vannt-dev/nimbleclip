/// A video whose picture and sound arrive as two streams, to be joined on the
/// device into one MP4.
///
/// YouTube serves nothing above 360p with sound: higher qualities are a
/// video-only stream plus a separate audio stream. Like `SlideshowSource`, it
/// carries URLs rather than files, since fetching belongs to the service layer.
class MergeSource {
  const MergeSource({
    required this.videoUrl,
    required this.audioUrl,
    this.videoBytes,
    this.audioBytes,
  });

  final String videoUrl;
  final String audioUrl;

  /// Sizes as the source reported them; used to weight the fetch progress.
  final int? videoBytes;
  final int? audioBytes;
}
