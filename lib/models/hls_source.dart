/// A video served as an HLS stream: a playlist naming the segments it is cut
/// into, to be fetched one by one and joined on the device into one MP4.
///
/// Like `MergeSource` it carries URLs rather than files. The playlists are
/// read again when the download starts, since segment addresses are often
/// signed and short-lived.
class HlsSource {
  const HlsSource({
    required this.videoPlaylistUrl,
    this.audioPlaylistUrl,
    String? playlistUrl,
  }) : playlistUrl = playlistUrl ?? videoPlaylistUrl;

  /// The playlist the link led to, which a player can be handed as it is:
  /// the master playlist when there is one, so picture and sound play
  /// together even when they are served apart.
  final String playlistUrl;

  /// The media playlist of the chosen quality.
  final String videoPlaylistUrl;

  /// The media playlist of the sound, when the stream carries it apart from
  /// the picture. Null when the video segments hold both.
  final String? audioPlaylistUrl;
}
