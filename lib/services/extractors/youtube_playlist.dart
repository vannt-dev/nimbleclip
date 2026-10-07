import 'dart:convert';

import '../../core/utils/http_helper.dart';
import '../../core/utils/json_scanner.dart';
import '../../core/utils/url_helper.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';
import 'parse_offloading.dart';

/// The videos a playlist page lists, in the playlist's own order.
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

/// The list id of a link to a playlist page, or null for any other link.
///
/// Only `/playlist?list=` counts. A `watch?v=…&list=…` link is one video that
/// happens to be playing from a list, and the person who shared it meant that
/// video.
String? youtubePlaylistIdFrom(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = UrlHelper.hostOf(url);
  if (!UrlHelper.hostMatches(host, 'youtube.com')) return null;
  if (uri.path != '/playlist' && uri.path != '/playlist/') return null;
  final id = uri.queryParameters['list'] ?? '';
  return _playlistId.hasMatch(id) ? id : null;
}

final RegExp _playlistId = RegExp(r'^[\w-]{10,}$');
final RegExp _videoId = RegExp(r'^[\w-]{11}$');

/// Reads the videos out of a playlist page's `ytInitialData`.
///
/// Top-level so it can run on a background isolate: the page is about two
/// megabytes. YouTube has listed a playlist's rows in two shapes, the older
/// `playlistVideoRenderer` and the `lockupViewModel` that replaced it; both
/// are read, wherever under `contents` they sit.
YouTubePlaylist parseYouTubePlaylistPage(String body) {
  final blob = extractJsonAfterMarker(body, 'ytInitialData');
  if (blob == null) return const YouTubePlaylist(title: '', videoIds: []);

  final Object? data;
  try {
    data = jsonDecode(blob);
  } on FormatException {
    return const YouTubePlaylist(title: '', videoIds: []);
  }
  if (data is! Map<String, dynamic>) {
    return const YouTubePlaylist(title: '', videoIds: []);
  }

  final ids = <String>{};
  void walk(Object? node) {
    if (node is List) {
      node.forEach(walk);
      return;
    }
    if (node is! Map) return;

    final row = node['playlistVideoRenderer'];
    if (row is Map) {
      final id = row['videoId'];
      if (id is String && _videoId.hasMatch(id)) ids.add(id);
      return;
    }
    final lockup = node['lockupViewModel'];
    if (lockup is Map) {
      final id = lockup['contentId'];
      if (lockup['contentType'] == 'LOCKUP_CONTENT_TYPE_VIDEO' &&
          id is String &&
          _videoId.hasMatch(id)) {
        ids.add(id);
      }
      return;
    }
    node.values.forEach(walk);
  }

  walk(data['contents']);

  final metadata = data['metadata'];
  final renderer = metadata is Map
      ? metadata['playlistMetadataRenderer']
      : null;
  final title = renderer is Map ? renderer['title'] : null;
  return YouTubePlaylist(
    title: title is String ? title : '',
    videoIds: List.unmodifiable(ids),
  );
}

/// Fetches a playlist page and lists its videos.
///
/// The page carries the first hundred rows, which is all a batch of twenty
/// links can use, so the continuation requests behind "load more" are never
/// made.
class YouTubePlaylistReader {
  const YouTubePlaylistReader();

  Future<YouTubePlaylist> read(String url) async {
    final id = youtubePlaylistIdFrom(url);
    if (id == null) {
      throw ExtractionException(
        const ExtractionFailure(
          ExtractionFailureKind.youtubePlaylistUnavailable,
        ),
        diagnosticCode: 'youtube_playlist_invalid_link',
      );
    }

    final String body;
    try {
      final response = await ExtractorHttp.get(
        'https://www.youtube.com/playlist?list=$id',
      );
      body = response.body;
    } catch (e) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.youtubeLoadFailed,
          detail: e.toString(),
        ),
        diagnosticCode: 'youtube_playlist_load_failed',
      );
    }

    final playlist = await parseOffMainIsolate(
      parseYouTubePlaylistPage,
      body,
      debugLabel: 'youtube-playlist',
    );
    if (playlist.videoIds.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(
          ExtractionFailureKind.youtubePlaylistUnavailable,
        ),
        diagnosticCode: 'youtube_playlist_no_videos',
      );
    }
    return playlist;
  }
}
