import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/generic_extractor.dart';
import 'package:nimble_clip/services/hls/hls_fetcher.dart';
import 'package:nimble_clip/services/hls/hls_playlist.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';

const _master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Deutsch",DEFAULT=NO,URI="audio/de.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="English",DEFAULT=YES,URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="sub",NAME="English",URI="subs/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="aud"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="aud"
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,AUDIO="aud"
1080-high/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=720x1280
vertical/index.m3u8
''';

const _media = '''
#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
seg0.ts
#EXTINF:10.0,
seg1.ts
#EXTINF:4.5,
https://other.example/seg2.ts?token=a
#EXT-X-ENDLIST
''';

Matcher _extractionFails(ExtractionFailureKind kind) => throwsA(
  isA<ExtractionException>().having(
    (error) => error.failure.kind,
    'failure kind',
    kind,
  ),
);

Matcher _fetchFails(SlideshowFailureKind kind) => throwsA(
  isA<SlideshowException>().having((error) => error.kind, 'kind', kind),
);

void main() {
  final base = Uri.parse('https://cdn.example/video/master.m3u8');

  group('a master playlist', () {
    test('lists its qualities best first, by size then bitrate', () {
      final master = parseHlsMaster(_master, base);

      expect(master.variants.map((variant) => variant.url), [
        'https://cdn.example/video/1080-high/index.m3u8',
        'https://cdn.example/video/1080/index.m3u8',
        'https://cdn.example/video/vertical/index.m3u8',
        'https://cdn.example/video/360/index.m3u8',
      ]);
    });

    test('names a vertical video after its short side', () {
      final vertical = parseHlsMaster(
        _master,
        base,
      ).variants.firstWhere((variant) => variant.url.contains('vertical'));

      expect(vertical.shortSide, 720);
      expect(vertical.audioGroup, isNull);
    });

    test('takes the default language of an audio group', () {
      final master = parseHlsMaster(_master, base);

      expect(master.audio, {'aud': 'https://cdn.example/video/audio/en.m3u8'});
    });

    test('is told apart from a media playlist', () {
      expect(isHlsMaster(_master), isTrue);
      expect(isHlsMaster(_media), isFalse);
    });
  });

  group('a media playlist', () {
    test('lists its segments in order, resolved against its address', () {
      final media = parseHlsMedia(_media, base);

      expect(media.segments.map((segment) => segment.url), [
        'https://cdn.example/video/seg0.ts',
        'https://cdn.example/video/seg1.ts',
        'https://other.example/seg2.ts?token=a',
      ]);
      expect(media.isComplete, isTrue);
      expect(media.isEncrypted, isFalse);
      expect(media.initialization, isNull);
      expect(media.duration, const Duration(milliseconds: 24500));
    });

    test('without an end is a live stream', () {
      final media = parseHlsMedia(
        _media.replaceFirst('#EXT-X-ENDLIST', ''),
        base,
      );

      expect(media.isComplete, isFalse);
    });

    String withKey(String key) =>
        _media.replaceFirst('#EXT-X-TARGETDURATION:10', key);

    test('names the key of each segment it has to be decrypted with', () {
      final media = parseHlsMedia(
        withKey(
          '#EXT-X-MEDIA-SEQUENCE:7\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="keys/a.key"',
        ).replaceFirst(
          '#EXTINF:4.5,',
          '#EXT-X-KEY:METHOD=AES-128,URI="https://k.example/b.key",'
              'IV=0x000102030405060708090a0b0c0d0e0f\n#EXTINF:4.5,',
        ),
        base,
      );

      expect(media.isEncrypted, isFalse);
      expect(media.needsKey, isTrue);
      expect(media.segments.map((segment) => segment.key!.uri), [
        'https://cdn.example/video/keys/a.key',
        'https://cdn.example/video/keys/a.key',
        'https://k.example/b.key',
      ]);
      // No vector given: the segment's number in the stream, big-endian.
      expect(media.segments[0].initializationVector, [
        ...List.filled(15, 0),
        7,
      ]);
      expect(media.segments[1].initializationVector.last, 8);
      expect(
        media.segments[2].initializationVector,
        List.generate(16, (index) => index),
      );
    });

    test('is protected when the key is not one a player can fetch', () {
      for (final key in const [
        '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://key-id"',
        '#EXT-X-KEY:METHOD=AES-128,URI="skd://key-id"',
        '#EXT-X-KEY:METHOD=SAMPLE-AES-CTR,URI="data:text/plain;base64,AAAA"',
      ]) {
        expect(parseHlsMedia(withKey(key), base).isEncrypted, isTrue);
      }
      final open = parseHlsMedia(withKey('#EXT-X-KEY:METHOD=NONE'), base);
      expect(open.isEncrypted, isFalse);
      expect(open.needsKey, isFalse);
    });

    test('reads byte ranges of one file, each following the last', () {
      final media = parseHlsMedia('''
#EXTM3U
#EXT-X-MAP:URI="main.mp4",BYTERANGE="719@0"
#EXTINF:6.0,
#EXT-X-BYTERANGE:1000@719
main.mp4
#EXTINF:6.0,
#EXT-X-BYTERANGE:500
main.mp4
#EXT-X-ENDLIST
''', base);

      expect(media.initialization!.url, 'https://cdn.example/video/main.mp4');
      expect(media.initialization!.range, (start: 0, length: 719));
      expect(media.segments.map((segment) => segment.range), [
        (start: 719, length: 1000),
        (start: 1719, length: 500),
      ]);
    });
  });

  group('fetching a stream', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('hls_test');
    });
    tearDown(() => workspace.deleteSync(recursive: true));

    const playlist = 'https://cdn.example/video/360/index.m3u8';

    MockClient serving(
      Map<String, String> bodies, {
      List<http.Request>? requests,
    }) => MockClient((request) async {
      requests?.add(request);
      final body = bodies[request.url.toString()];
      return body == null ? http.Response('', 404) : http.Response(body, 200);
    });

    test('writes the segments end to end in playing order', () async {
      final into = File('${workspace.path}/video.stream');
      final progress = <double>[];

      await fetchHlsToFile(
        playlist,
        into,
        concurrency: 2,
        client: serving({
          playlist: _media,
          'https://cdn.example/video/360/seg0.ts': 'AAA',
          'https://cdn.example/video/360/seg1.ts': 'BB',
          'https://other.example/seg2.ts?token=a': 'C',
        }),
        onProgress: (fraction, _) => progress.add(fraction),
      );

      expect(into.readAsStringSync(), 'AAABBC');
      expect(progress.last, 1.0);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('puts the initialization header first and asks for ranges', () async {
      final into = File('${workspace.path}/video.stream');
      final requests = <http.Request>[];

      await fetchHlsToFile(
        playlist,
        into,
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.toString() == playlist) {
            return http.Response('''
#EXTM3U
#EXT-X-MAP:URI="main.mp4",BYTERANGE="4@0"
#EXTINF:6.0,
#EXT-X-BYTERANGE:3@4
main.mp4
#EXT-X-ENDLIST
''', 200);
          }
          return http.Response(
            request.headers['Range'] == 'bytes=0-3' ? 'INIT' : 'SEG',
            206,
          );
        }),
      );

      expect(into.readAsStringSync(), 'INITSEG');
      expect(requests.map((request) => request.headers['Range']), [
        null,
        'bytes=0-3',
        'bytes=4-6',
      ]);
    });

    test('decrypts each segment with its key and its place', () async {
      final into = File('${workspace.path}/video.stream');
      final calls = <({String body, List<int> key, int lastVectorByte})>[];
      var keyRequests = 0;

      await fetchHlsToFile(
        playlist,
        into,
        concurrency: 2,
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url == playlist) {
            return http.Response(
              _media.replaceFirst(
                '#EXT-X-TARGETDURATION:10',
                '#EXT-X-MEDIA-SEQUENCE:5\n'
                    '#EXT-X-KEY:METHOD=AES-128,URI="stream.key"',
              ),
              200,
            );
          }
          if (url.endsWith('stream.key')) {
            keyRequests++;
            return http.Response.bytes(List.generate(16, (i) => i + 1), 200);
          }
          return http.Response('locked-${url.split('/').last}', 200);
        }),
        // Stands in for the cipher: records what it was handed and writes
        // something recognisable in its place.
        decryptor: (encrypted, plain, key, vector) async {
          final body = encrypted.readAsStringSync();
          calls.add((body: body, key: key, lastVectorByte: vector.last));
          plain.writeAsStringSync('[${body.replaceFirst('locked-', '')}]');
        },
      );

      expect(keyRequests, 1);
      expect(
        calls.map((call) => call.lastVectorByte),
        unorderedEquals([5, 6, 7]),
      );
      expect(calls.every((call) => call.key.length == 16), isTrue);
      expect(into.readAsStringSync(), '[seg0.ts][seg1.ts][seg2.ts?token=a]');
    });

    test('refuses a key that is not a key', () async {
      await expectLater(
        fetchHlsToFile(
          playlist,
          File('${workspace.path}/video.stream'),
          client: MockClient((request) async {
            if (request.url.toString() == playlist) {
              return http.Response(
                _media.replaceFirst(
                  '#EXT-X-TARGETDURATION:10',
                  '#EXT-X-KEY:METHOD=AES-128,URI="stream.key"',
                ),
                200,
              );
            }
            return http.Response('<html>Please sign in</html>', 200);
          }),
          decryptor: (_, _, _, _) async => fail('nothing to decrypt with'),
        ),
        _fetchFails(SlideshowFailureKind.streamProtected),
      );
    });

    test('refuses a live stream and an encrypted one', () async {
      final into = File('${workspace.path}/video.stream');

      await expectLater(
        fetchHlsToFile(
          playlist,
          into,
          client: serving({
            playlist: _media.replaceFirst('#EXT-X-ENDLIST', ''),
          }),
        ),
        _fetchFails(SlideshowFailureKind.streamLive),
      );
      await expectLater(
        fetchHlsToFile(
          playlist,
          into,
          client: serving({
            playlist: _media.replaceFirst(
              '#EXT-X-TARGETDURATION:10',
              '#EXT-X-KEY:METHOD=AES-128,URI="key"',
            ),
          }),
        ),
        _fetchFails(SlideshowFailureKind.streamProtected),
      );
    });

    test('fails when a segment is missing', () async {
      await expectLater(
        fetchHlsToFile(
          playlist,
          File('${workspace.path}/video.stream'),
          client: serving({playlist: _media}),
        ),
        _fetchFails(SlideshowFailureKind.fetchFailed),
      );
    });

    test('gives up a stalled request and asks again', () async {
      final into = File('${workspace.path}/video.stream');
      var askedForFirst = 0;

      await fetchHlsToFile(
        playlist,
        into,
        segmentTimeout: const Duration(milliseconds: 50),
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url == playlist) return http.Response(_media, 200);
          if (url.endsWith('seg0.ts') && askedForFirst++ == 0) {
            // The first answer never comes.
            await Future<void>.delayed(const Duration(seconds: 2));
          }
          return http.Response('S', 200);
        }),
      );

      expect(askedForFirst, 2);
      expect(into.readAsStringSync(), 'SSS');
    });

    test('stops between segments when cancelled', () async {
      var asked = 0;

      await expectLater(
        fetchHlsToFile(
          playlist,
          File('${workspace.path}/video.stream'),
          concurrency: 1,
          client: serving({
            playlist: _media,
            'https://cdn.example/video/360/seg0.ts': 'AAA',
          }),
          isCancelled: () => asked++ > 0,
        ),
        _fetchFails(SlideshowFailureKind.cancelled),
      );
    });
  });

  group('a link to a stream', () {
    tearDown(ExtractorHttp.resetOverrides);

    const page = 'https://video.example/watch/42';
    const extractor = GenericExtractor(canJoinStreams: true);

    void serve(Map<String, String> bodies) {
      ExtractorHttp.getOverride = (uri, _) async {
        final body = bodies[uri.toString()];
        return body == null
            ? http.Response('', 404)
            : http.Response(
                body,
                200,
                headers: {
                  'content-type': body.startsWith('#EXTM3U')
                      ? 'application/vnd.apple.mpegurl'
                      : 'text/html; charset=utf-8',
                },
              );
      };
    }

    test('offers one download per size of a master playlist', () async {
      serve({
        'https://cdn.example/video/master.m3u8': _master.trimLeft(),
        'https://cdn.example/video/1080-high/index.m3u8': _media.trimLeft(),
      });

      final result = await extractor.extract(
        'https://cdn.example/video/master.m3u8',
      );

      expect(result.qualities.map((option) => option.quality), [
        '1080p',
        '720p',
        '360p',
      ]);
      expect(result.qualities.every((option) => option.needsRendering), isTrue);
      expect(result.qualities.first.label, isA<VideoWithAudio>());
      expect(result.duration, const Duration(milliseconds: 24500));

      final best = result.qualities.first.stream! as HlsSource;
      expect(
        best.videoPlaylistUrl,
        'https://cdn.example/video/1080-high/index.m3u8',
      );
      expect(best.audioPlaylistUrl, 'https://cdn.example/video/audio/en.m3u8');
      // The vertical quality carries its sound in the video segments.
      expect(
        (result.qualities[1].stream! as HlsSource).audioPlaylistUrl,
        isNull,
      );
    });

    test(
      'prefers H.264 with AAC where a size is listed in several codecs',
      () async {
        serve({
          'https://cdn.example/video/master.m3u8': '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",DEFAULT=YES,URI="audio/aac.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="dolby",DEFAULT=YES,URI="audio/ac3.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,CODECS="avc1.640020,ac-3",AUDIO="dolby"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.640020,mp4a.40.2",AUDIO="aac"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=3840x2160,CODECS="hvc1.2.4.L150,ec-3",AUDIO="dolby"
2160/index.m3u8
''',
          'https://cdn.example/video/2160/index.m3u8': _media.trimLeft(),
        });

        final result = await extractor.extract(
          'https://cdn.example/video/master.m3u8',
        );

        expect(result.qualities.map((option) => option.quality), [
          '2160p',
          '720p',
        ]);
        expect(
          (result.qualities.last.stream! as HlsSource).audioPlaylistUrl,
          'https://cdn.example/video/audio/aac.m3u8',
        );
        // A size offered only in another codec is still offered: the device
        // may well manage it, and says so plainly when it cannot.
        expect(
          (result.qualities.first.stream! as HlsSource).audioPlaylistUrl,
          'https://cdn.example/video/audio/ac3.m3u8',
        );
      },
    );

    test('offers a media playlist as the one quality it is', () async {
      serve({'https://cdn.example/video/360/index.m3u8': _media.trimLeft()});

      final result = await extractor.extract(
        'https://cdn.example/video/360/index.m3u8',
      );

      expect(result.qualities.single.label, isA<OriginalVideo>());
      expect(
        (result.qualities.single.stream! as HlsSource).videoPlaylistUrl,
        'https://cdn.example/video/360/index.m3u8',
      );
    });

    test('is found in the script of a page that declares no file', () async {
      serve({
        page:
            '<html><head><title>Clip</title>'
            '<meta property="og:image" content="/poster.jpg"></head><body>'
            r'<script>player.setup({"file":"https:\/\/cdn.example\/video\/'
            r'360\/index.m3u8?sig=1\u0026exp=2"});</script></body></html>',
        'https://cdn.example/video/360/index.m3u8?sig=1&exp=2': _media
            .trimLeft(),
      });

      final result = await extractor.extract(page);

      // The stream, not the poster picture the page also declares.
      expect(result.qualities.single.needsRendering, isTrue);
      expect(result.title, 'Clip');
      expect(result.coverUrl, 'https://video.example/poster.jpg');
    });

    test('says when the stream is live or encrypted', () async {
      serve({
        'https://cdn.example/live.m3u8': _media.trimLeft().replaceFirst(
          '#EXT-X-ENDLIST',
          '',
        ),
        'https://cdn.example/locked.m3u8': _media.trimLeft().replaceFirst(
          '#EXT-X-TARGETDURATION:10',
          '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://key"',
        ),
      });

      await expectLater(
        extractor.extract('https://cdn.example/live.m3u8'),
        _extractionFails(ExtractionFailureKind.genericStreamLive),
      );
      await expectLater(
        extractor.extract('https://cdn.example/locked.m3u8'),
        _extractionFails(ExtractionFailureKind.genericStreamProtected),
      );
    });

    test('is reported as a stream where it cannot be joined', () async {
      serve({'https://cdn.example/video/360/index.m3u8': _media.trimLeft()});

      await expectLater(
        const GenericExtractor(
          canJoinStreams: false,
        ).extract('https://cdn.example/video/360/index.m3u8'),
        _extractionFails(ExtractionFailureKind.genericStreamOnly),
      );
    });

    test('leaves a page with a file to the file', () async {
      serve({
        page:
            '<html><body><video src="/clip.mp4"></video>'
            '<script>var hls = "https://cdn.example/video/360/index.m3u8";'
            '</script></body></html>',
      });

      final result = await extractor.extract(page);

      expect(
        result.qualities.single.downloadUrl,
        'https://video.example/clip.mp4',
      );
    });
  });
}
