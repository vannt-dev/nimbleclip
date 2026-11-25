import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nimble_clip/services/lyrics/lrclib_client.dart';
import 'package:nimble_clip/services/lyrics/lyrics_query.dart';

const _synced = '[00:17.12] I feel your breath upon my neck\n[00:20.00] Next';
const _plain = 'I feel your breath upon my neck\nNext';

Map<String, Object?> _record({
  double duration = 233,
  bool instrumental = false,
  String? synced = _synced,
  String? plain = _plain,
}) => {
  'id': 1,
  'trackName': 'I Want to Live',
  'artistName': 'Borislav Slavov',
  'duration': duration,
  'instrumental': instrumental,
  'plainLyrics': plain,
  'syncedLyrics': synced,
};

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

final _notFound = _json({
  'message': 'Failed to find specified track',
  'name': 'TrackNotFound',
  'statusCode': 404,
}, 404);

const _query = LyricsQuery(
  artist: 'Borislav Slavov',
  track: 'I Want to Live',
  duration: Duration(seconds: 233),
);

void main() {
  late List<http.Request> requests;

  LrclibClient client(
    FutureOr<http.Response> Function(http.Request request) answer, {
    Duration timeout = const Duration(seconds: 6),
  }) => LrclibClient(
    client: MockClient((request) async {
      requests.add(request);
      return answer(request);
    }),
    userAgent: () async => 'NimbleClip v9.9.9 (https://example.com/repo)',
    timeout: timeout,
  );

  setUp(() => requests = []);

  group('lyricsFromRecord', () {
    test('prefers the synced lyrics', () {
      final lyrics = lyricsFromRecord(_record())!;
      expect(lyrics.synced, isTrue);
      expect(lyrics.text, _synced);
    });

    test('falls back to the plain lyrics', () {
      final lyrics = lyricsFromRecord(_record(synced: null))!;
      expect(lyrics.synced, isFalse);
      expect(lyrics.text, _plain);
    });

    test('gives nothing for an instrumental', () {
      expect(
        lyricsFromRecord(
          _record(instrumental: true, synced: null, plain: null),
        ),
        isNull,
      );
    });

    test('gives nothing for a record with empty lyrics', () {
      expect(lyricsFromRecord(_record(synced: ' ', plain: '')), isNull);
      expect(lyricsFromRecord('not a record'), isNull);
    });
  });

  group('bestSearchMatch', () {
    test('takes the closest length within three seconds', () {
      final lyrics = bestSearchMatch([
        _record(duration: 300, synced: 'far'),
        _record(duration: 235, synced: 'near'),
        _record(duration: 232, synced: 'nearest'),
      ], const Duration(seconds: 233))!;
      expect(lyrics.text, 'nearest');
    });

    test('prefers synced lyrics at the same distance', () {
      final lyrics = bestSearchMatch([
        _record(synced: null, plain: 'plain'),
        _record(synced: 'synced'),
      ], const Duration(seconds: 233))!;
      expect(lyrics.synced, isTrue);
    });

    test('gives nothing when every length is too far off', () {
      expect(
        bestSearchMatch([
          _record(duration: 240),
          _record(duration: 229),
        ], const Duration(seconds: 233)),
        isNull,
      );
    });

    test('skips instrumentals and malformed entries', () {
      expect(
        bestSearchMatch([
          _record(instrumental: true, synced: null, plain: null),
          {'duration': 'long'},
          null,
        ], const Duration(seconds: 233)),
        isNull,
      );
    });
  });

  group('LrclibClient.find', () {
    test(
      'asks for the track by its signature, as an identified client',
      () async {
        final lyrics = await client((_) => _json(_record())).find(_query);

        expect(lyrics!.synced, isTrue);
        final request = requests.single;
        expect(request.url.host, 'lrclib.net');
        expect(request.url.path, '/api/get');
        expect(request.url.queryParameters, {
          'artist_name': 'Borislav Slavov',
          'track_name': 'I Want to Live',
          'duration': '233',
        });
        expect(
          request.headers['User-Agent'],
          'NimbleClip v9.9.9 (https://example.com/repo)',
        );
      },
    );

    test('returns plain lyrics when only those exist', () async {
      final lyrics = await client(
        (_) => _json(_record(synced: null)),
      ).find(_query);
      expect(lyrics!.synced, isFalse);
      expect(lyrics.text, _plain);
    });

    test('returns nothing for an instrumental', () async {
      final lyrics = await client(
        (_) => _json(_record(instrumental: true, synced: null, plain: null)),
      ).find(_query);
      expect(lyrics, isNull);
      expect(requests, hasLength(1));
    });

    test('searches when the signature is not found', () async {
      final lyrics = await client(
        (request) => request.url.path == '/api/get'
            ? _notFound
            : _json([
                _record(duration: 260, synced: 'other recording'),
                _record(duration: 231, synced: 'this recording'),
              ]),
      ).find(_query);

      expect(lyrics!.text, 'this recording');
      expect(requests.map((r) => r.url.path), ['/api/get', '/api/search']);
      expect(
        requests.last.url.queryParameters['q'],
        'Borislav Slavov I Want to Live',
      );
    });

    test('gives nothing when neither finds it', () async {
      final lyrics = await client(
        (request) => request.url.path == '/api/get' ? _notFound : _json([]),
      ).find(_query);
      expect(lyrics, isNull);
      expect(requests, hasLength(2));
    });

    test('does not guess from a search without the track length', () async {
      final lyrics = await client((_) => _notFound).find(
        const LyricsQuery(artist: 'Borislav Slavov', track: 'I Want to Live'),
      );
      expect(lyrics, isNull);
      expect(requests.single.url.path, '/api/get');
      expect(requests.single.url.queryParameters, isNot(contains('duration')));
    });

    test('searches straight away when there is no artist', () async {
      final lyrics = await client((_) => _json([_record()])).find(
        const LyricsQuery(
          artist: '',
          track: 'I Want to Live',
          duration: Duration(seconds: 233),
        ),
      );
      expect(lyrics, isNotNull);
      expect(requests.single.url.path, '/api/search');
      expect(requests.single.url.queryParameters['q'], 'I Want to Live');
    });

    test('gives up quietly on a server error or a refusal', () async {
      for (final status in [429, 500, 503]) {
        requests.clear();
        final lyrics = await client(
          (_) => _json({'statusCode': status}, status),
        ).find(_query);
        expect(lyrics, isNull, reason: 'status $status');
        expect(requests, hasLength(1), reason: 'no retry after $status');
      }
    });

    test('gives up quietly on a body that is not JSON', () async {
      final lyrics = await client(
        (_) => http.Response('<html>busy</html>', 200),
      ).find(_query);
      expect(lyrics, isNull);
    });

    test('gives up quietly when the network fails', () async {
      final lyrics = await client(
        (_) => throw http.ClientException('offline'),
      ).find(_query);
      expect(lyrics, isNull);
    });

    test('gives up when the service takes too long', () async {
      final never = Completer<http.Response>();
      final lyrics = await client(
        (_) => never.future,
        timeout: const Duration(milliseconds: 50),
      ).find(_query);
      expect(lyrics, isNull);
    });
  });
}
