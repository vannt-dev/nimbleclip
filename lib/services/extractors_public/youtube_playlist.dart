import 'base_extractor.dart';
import 'extraction_failure.dart';

/// The videos a playlist page lists. The public core reads no playlist; the
/// type is here because the app is written against it.
class YouTubePlaylist {
  const YouTubePlaylist({required this.title, required this.videoIds});

  final String title;
  final List<String> videoIds;

  /// Watch links for the first [limit] videos.
  List<String> videoUrls({required int limit}) => [
    for (final id in videoIds.take(limit))
      'https://www.youtube.com/watch?v=$id',
  ];
}

/// The list id of a link to a playlist page. Always null here, so the app
/// never takes a link for a playlist it could not read.
String? youtubePlaylistIdFrom(String url) => null;

class YouTubePlaylistReader {
  const YouTubePlaylistReader();

  Future<YouTubePlaylist> read(String url) async {
    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.youtubePlaylistUnavailable),
      diagnosticCode: 'public_core',
    );
  }
}
