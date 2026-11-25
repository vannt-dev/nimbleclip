import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/app_constants.dart';
import 'lyrics_query.dart';

/// Lyrics found for a track: LRC text with line timings when [synced], or
/// the plain words otherwise.
class Lyrics {
  const Lyrics({required this.text, required this.synced});

  final String text;
  final bool synced;
}

/// Somewhere lyrics can be looked up.
abstract interface class LyricsSource {
  /// The lyrics for [query], or null when there are none: not found, an
  /// instrumental, or the service could not be reached in time. Never throws.
  Future<Lyrics?> find(LyricsQuery query);
}

/// Looks lyrics up on LRCLIB (https://lrclib.net), a free, open lyrics
/// catalogue that needs no account or key.
class LrclibClient implements LyricsSource {
  LrclibClient({
    http.Client? client,
    Future<String> Function()? userAgent,
    this.timeout = const Duration(seconds: 6),
    Uri? baseUri,
  }) : _client = client ?? http.Client(),
       _userAgent = userAgent ?? _appUserAgent,
       _baseUri = baseUri ?? Uri.parse('https://lrclib.net');

  final http.Client _client;
  final Future<String> Function() _userAgent;
  final Uri _baseUri;

  /// The longest a whole lookup may take, both requests together.
  final Duration timeout;

  /// How far a search result's length may be from the track's and still be
  /// taken as the same recording.
  static const Duration searchTolerance = Duration(seconds: 3);

  @override
  Future<Lyrics?> find(LyricsQuery query) async {
    try {
      return await _find(query).timeout(timeout);
    } catch (_) {
      // Best effort: a slow or unreachable service simply means no lyrics.
      return null;
    }
  }

  Future<Lyrics?> _find(LyricsQuery query) async {
    final headers = {'User-Agent': await _userAgent()};
    final seconds = query.duration?.inSeconds;
    final duration = seconds != null && seconds >= 1 && seconds <= 3600
        ? seconds
        : null;
    if (query.artist.isNotEmpty) {
      final response = await _client.get(
        _baseUri.replace(
          path: '/api/get',
          queryParameters: {
            'artist_name': query.artist,
            'track_name': query.track,
            'duration': ?duration?.toString(),
          },
        ),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return lyricsFromRecord(_decode(response));
      }
      if (response.statusCode != 404) return null;
    }
    // Without the track's length a search result cannot be told apart from
    // another recording of the same name, so nothing is guessed.
    if (duration == null) return null;
    final response = await _client.get(
      _baseUri.replace(
        path: '/api/search',
        queryParameters: {
          'q': [query.artist, query.track].where((s) => s.isNotEmpty).join(' '),
        },
      ),
      headers: headers,
    );
    if (response.statusCode != 200) return null;
    final results = _decode(response);
    if (results is! List) return null;
    return bestSearchMatch(results, Duration(seconds: duration));
  }

  static Object? _decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes));

  static Future<String>? _cachedUserAgent;

  /// `NimbleClip v1.2.3 (https://github.com/vannt-dev/nimbleclip)`, the form
  /// LRCLIB asks clients to identify themselves with.
  static Future<String> _appUserAgent() => _cachedUserAgent ??= () async {
    var version = '';
    try {
      version = ' v${(await PackageInfo.fromPlatform()).version}';
    } catch (_) {}
    return '${AppConstants.appName}$version (${AppConstants.appRepoUrl})';
  }();
}

/// The lyrics in one LRCLIB record: the synced text when it has one, else
/// the plain text. Null for an instrumental or a record without either.
Lyrics? lyricsFromRecord(Object? record) {
  if (record is! Map) return null;
  if (record['instrumental'] == true) return null;
  final synced = record['syncedLyrics'];
  if (synced is String && synced.trim().isNotEmpty) {
    return Lyrics(text: synced, synced: true);
  }
  final plain = record['plainLyrics'];
  if (plain is String && plain.trim().isNotEmpty) {
    return Lyrics(text: plain, synced: false);
  }
  return null;
}

/// The search result closest in length to [duration], within
/// [LrclibClient.searchTolerance], that has lyrics. A synced one is preferred
/// over a plain one of the same closeness.
Lyrics? bestSearchMatch(List<Object?> results, Duration duration) {
  Lyrics? best;
  var bestDistance = double.infinity;
  final target = duration.inMilliseconds / 1000;
  final tolerance = LrclibClient.searchTolerance.inSeconds;
  for (final record in results) {
    if (record is! Map) continue;
    final length = record['duration'];
    if (length is! num) continue;
    final distance = (length - target).abs();
    if (distance > tolerance) continue;
    final lyrics = lyricsFromRecord(record);
    if (lyrics == null) continue;
    final better =
        distance < bestDistance ||
        (distance == bestDistance && lyrics.synced && !(best?.synced ?? true));
    if (better) {
      best = lyrics;
      bestDistance = distance;
    }
  }
  return best;
}
