import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/extractors/youtube_playlist.dart';

const _playlistUrl =
    'https://www.youtube.com/playlist?list=PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI';

/// Eleven characters, as a real video id is.
String _videoId(int index) => 'vid${index.toString().padLeft(8, '0')}';

String _watchUrl(int index) =>
    'https://www.youtube.com/watch?v=${_videoId(index)}';

/// A playlist page as YouTube serves it now: each row a `lockupViewModel`.
String _lockupPage(List<String> ids, {String title = 'Fixture list'}) {
  final data = {
    'contents': {
      'twoColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          for (final id in ids)
                            {
                              'lockupViewModel': {
                                'contentId': id,
                                'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
                                'metadata': {'title': 'a } brace in a title'},
                              },
                            },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
    'metadata': {
      'playlistMetadataRenderer': {'title': title},
    },
  };
  return '<html><script>var ytInitialData = ${jsonEncode(data)};</script></html>';
}

class _RecordingRegistry extends ExtractorRegistry {
  final List<String> requested = [];

  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    requested.add(rawUrl);
    return VideoMetadata(
      id: rawUrl,
      originalUrl: rawUrl,
      title: rawUrl,
      author: 'Fixture',
      coverUrl: '',
      platform: VideoPlatform.youtube,
      qualities: [
        VideoQualityOption.video(
          id: rawUrl,
          label: const Hd720(),
          quality: '720p',
          format: 'mp4',
          downloadUrl: '$rawUrl/video.mp4',
        ),
      ],
    );
  }
}

class _FixturePlaylistReader extends YouTubePlaylistReader {
  const _FixturePlaylistReader(this.count);

  final int count;

  @override
  Future<YouTubePlaylist> read(String url) async => YouTubePlaylist(
    title: 'Fixture list',
    videoIds: [for (var i = 0; i < count; i++) _videoId(i)],
  );
}

class _UnreadablePlaylistReader extends YouTubePlaylistReader {
  const _UnreadablePlaylistReader();

  @override
  Future<YouTubePlaylist> read(String url) async {
    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.youtubePlaylistUnavailable),
      diagnosticCode: 'youtube_playlist_no_videos',
    );
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('youtubePlaylistIdFrom', () {
    test('reads the list id of a playlist page', () {
      expect(
        youtubePlaylistIdFrom(_playlistUrl),
        'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI',
      );
      expect(
        youtubePlaylistIdFrom(
          'https://music.youtube.com/playlist?list=OLAK5uy_abcdefghij&si=x',
        ),
        'OLAK5uy_abcdefghij',
      );
      expect(
        youtubePlaylistIdFrom(
          'https://m.youtube.com/playlist?list=PL0123456789',
        ),
        'PL0123456789',
      );
    });

    test('a video playing from a list is still one video', () {
      expect(
        youtubePlaylistIdFrom(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL0123456789',
        ),
        isNull,
      );
    });

    test('ignores other hosts and playlist pages without a list', () {
      expect(
        youtubePlaylistIdFrom('https://example.com/playlist?list=PL0123456789'),
        isNull,
      );
      expect(
        youtubePlaylistIdFrom(
          'https://evil.example.com/?next=youtube.com/playlist?list=PL0123456789',
        ),
        isNull,
      );
      expect(youtubePlaylistIdFrom('https://www.youtube.com/playlist'), isNull);
      expect(
        youtubePlaylistIdFrom('https://www.youtube.com/playlist?list=a b'),
        isNull,
      );
    });
  });

  group('parseYouTubePlaylistPage', () {
    test('lists lockup rows in order, once each, with the title', () {
      final ids = [_videoId(1), _videoId(2), _videoId(1), _videoId(3)];

      final playlist = parseYouTubePlaylistPage(_lockupPage(ids));

      expect(playlist.title, 'Fixture list');
      expect(playlist.videoIds, [_videoId(1), _videoId(2), _videoId(3)]);
    });

    test('reads the older playlistVideoRenderer rows', () {
      final data = {
        'contents': {
          'playlistVideoListRenderer': {
            'contents': [
              {
                'playlistVideoRenderer': {'videoId': _videoId(7)},
              },
              {
                'playlistVideoRenderer': {'videoId': _videoId(8)},
              },
            ],
          },
        },
      };

      final playlist = parseYouTubePlaylistPage(
        'ytInitialData = ${jsonEncode(data)};',
      );

      expect(playlist.videoIds, [_videoId(7), _videoId(8)]);
      expect(playlist.title, '');
    });

    test('skips rows that are not videos and anything outside contents', () {
      final data = {
        'contents': [
          {
            'lockupViewModel': {
              'contentId': 'PL0123456789',
              'contentType': 'LOCKUP_CONTENT_TYPE_PLAYLIST',
            },
          },
          {
            'lockupViewModel': {
              'contentId': _videoId(1),
              'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
            },
          },
        ],
        'sidebar': {
          'lockupViewModel': {
            'contentId': _videoId(9),
            'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
          },
        },
      };

      final playlist = parseYouTubePlaylistPage(
        'ytInitialData = ${jsonEncode(data)};',
      );

      expect(playlist.videoIds, [_videoId(1)]);
    });

    test('a page without the data lists nothing', () {
      expect(parseYouTubePlaylistPage('<html></html>').videoIds, isEmpty);
      expect(
        parseYouTubePlaylistPage('ytInitialData = {"contents": [}').videoIds,
        isEmpty,
      );
    });
  });

  group('YouTubePlaylistReader', () {
    tearDown(() => ExtractorHttp.getOverride = null);

    test('fetches the canonical playlist page and lists its videos', () async {
      Uri? requested;
      ExtractorHttp.getOverride = (uri, headers) async {
        requested = uri;
        return http.Response(_lockupPage([_videoId(1), _videoId(2)]), 200);
      };

      final playlist = await const YouTubePlaylistReader().read(
        'https://music.youtube.com/playlist?list=PL0123456789&si=share',
      );

      expect(
        requested.toString(),
        'https://www.youtube.com/playlist?list=PL0123456789',
      );
      expect(playlist.videoUrls(limit: 1), [_watchUrl(1)]);
    });

    test('a page that lists no videos is reported as unavailable', () async {
      ExtractorHttp.getOverride = (uri, headers) async =>
          http.Response('<html>consent</html>', 200);

      await expectLater(
        const YouTubePlaylistReader().read(_playlistUrl),
        throwsA(
          isA<ExtractionException>().having(
            (error) => error.failure.kind,
            'kind',
            ExtractionFailureKind.youtubePlaylistUnavailable,
          ),
        ),
      );
    });

    test('a failed request is reported as a load failure', () async {
      ExtractorHttp.getOverride = (uri, headers) async =>
          throw const FormatException('offline');

      await expectLater(
        const YouTubePlaylistReader().read(_playlistUrl),
        throwsA(
          isA<ExtractionException>().having(
            (error) => error.failure.kind,
            'kind',
            ExtractionFailureKind.youtubeLoadFailed,
          ),
        ),
      );
    });
  });

  group('analyzeUrls with a playlist link', () {
    test('analyzes the playlist videos in place of the link', () async {
      final registry = _RecordingRegistry();
      final provider = VideoExtractorProvider(
        extractorRegistry: registry,
        playlistReader: const _FixturePlaylistReader(3),
      );

      final results = await provider.analyzeUrls([
        'https://example.com/first',
        _playlistUrl,
        _watchUrl(1),
      ], l10n: l10n);

      // The video pasted on its own is already in the playlist, so it is
      // analyzed once.
      expect(results.map((result) => result.url), [
        'https://example.com/first',
        _watchUrl(0),
        _watchUrl(1),
        _watchUrl(2),
      ]);
      expect(registry.requested, isNot(contains(_playlistUrl)));
      expect(provider.batchTruncated, isFalse);
      expect(provider.isAnalyzing, isFalse);
    });

    test('a playlist longer than a batch is cut and says so', () async {
      final registry = _RecordingRegistry();
      final provider = VideoExtractorProvider(
        extractorRegistry: registry,
        playlistReader: const _FixturePlaylistReader(60),
      );

      final results = await provider.analyzeUrls([_playlistUrl], l10n: l10n);

      expect(results, hasLength(VideoExtractorProvider.maximumBatchUrls));
      expect(results.last.url, _watchUrl(19));
      expect(provider.batchTruncated, isTrue);
    });

    test('a playlist of one video opens as a single result', () async {
      final provider = VideoExtractorProvider(
        extractorRegistry: _RecordingRegistry(),
        playlistReader: const _FixturePlaylistReader(1),
      );

      final results = await provider.analyzeUrls([_playlistUrl], l10n: l10n);

      expect(results.single.url, _watchUrl(0));
      expect(provider.metadata?.originalUrl, _watchUrl(0));
      expect(provider.batchResults, isEmpty);
    });

    test('an unreadable playlist stays as a failed row', () async {
      final provider = VideoExtractorProvider(
        extractorRegistry: _RecordingRegistry(),
        playlistReader: const _UnreadablePlaylistReader(),
      );

      final results = await provider.analyzeUrls([
        'https://example.com/first',
        _playlistUrl,
      ], l10n: l10n);

      expect(results, hasLength(2));
      expect(results.first.isSuccess, isTrue);
      expect(results.last.url, _playlistUrl);
      expect(results.last.error, l10n.youtubePlaylistUnavailable);
      expect(results.last.diagnosticCode, 'youtube_playlist_no_videos');
    });

    test('an unreadable playlist on its own shows its error', () async {
      final provider = VideoExtractorProvider(
        extractorRegistry: _RecordingRegistry(),
        playlistReader: const _UnreadablePlaylistReader(),
      );

      final results = await provider.analyzeUrls([_playlistUrl], l10n: l10n);

      expect(results.single.error, l10n.youtubePlaylistUnavailable);
      expect(provider.errorMessage, l10n.youtubePlaylistUnavailable);
      expect(provider.isAnalyzing, isFalse);
    });

    test('links without a playlist never consult the reader', () async {
      final provider = VideoExtractorProvider(
        extractorRegistry: _RecordingRegistry(),
        playlistReader: const _UnreadablePlaylistReader(),
      );

      final results = await provider.analyzeUrls([
        'https://example.com/a',
        'https://example.com/b',
      ], l10n: l10n);

      expect(results.every((result) => result.isSuccess), isTrue);
      expect(provider.batchTruncated, isFalse);
    });
  });
}
