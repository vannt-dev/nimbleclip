/// A video served as a stream: an index naming the segments it is cut into,
/// to be fetched one by one and joined on the device into one MP4.
///
/// Like `MergeSource` it carries URLs rather than files. The index is read
/// again when the download starts, since segment addresses are often signed
/// and short-lived.
sealed class StreamSource {
  const StreamSource();

  /// The index the link led to, which a player can be handed as it is.
  String get playlistUrl;
}

/// An HLS stream, indexed by playlists.
class HlsSource extends StreamSource {
  const HlsSource({
    required this.videoPlaylistUrl,
    this.audioPlaylistUrl,
    String? playlistUrl,
  }) : playlistUrl = playlistUrl ?? videoPlaylistUrl;

  /// The master playlist when there is one, so picture and sound play
  /// together even when they are served apart.
  @override
  final String playlistUrl;

  /// The media playlist of the chosen quality.
  final String videoPlaylistUrl;

  /// The media playlist of the sound, when the stream carries it apart from
  /// the picture. Null when the video segments hold both.
  final String? audioPlaylistUrl;
}

/// A DASH stream, indexed by one manifest that lists every quality.
class DashSource extends StreamSource {
  const DashSource({
    required this.manifestUrl,
    required this.videoId,
    this.audioId,
  });

  final String manifestUrl;

  /// The `Representation` of the chosen quality.
  final String videoId;

  /// The `Representation` of the sound. Null when the manifest has none.
  final String? audioId;

  @override
  String get playlistUrl => manifestUrl;
}
