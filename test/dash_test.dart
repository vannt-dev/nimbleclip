import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/services/dash/dash_fetcher.dart';
import 'package:nimble_clip/services/dash/dash_manifest.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/generic_extractor.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';

String _mpd(String periods, {String attributes = ''}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
     mediaPresentationDuration="PT0H1M10.5S" $attributes>
$periods
</MPD>''';

/// Segments numbered from a pattern: a set-level template the representations
/// fill in, picture and sound apart.
final _numbered = _mpd('''
  <Period>
    <AdaptationSet mimeType="video/mp4" codecs="avc1.64001f">
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
          initialization="\$RepresentationID\$/init.mp4"
          media="\$RepresentationID\$/seg-\$Number%05d\$.m4s"/>
      <Representation id="v360" bandwidth="800000" width="640" height="360"/>
      <Representation id="v1080" bandwidth="5000000" width="1920" height="1080"/>
      <Representation id="v1080hevc" bandwidth="4000000" width="1920"
          height="1080" codecs="hvc1.1.6.L120"/>
    </AdaptationSet>
    <AdaptationSet contentType="audio" mimeType="audio/mp4">
      <SegmentTemplate timescale="48000" duration="192000"
          initialization="\$RepresentationID\$/init.mp4"
          media="\$RepresentationID\$/\$Number\$.m4s"/>
      <Representation id="ac3" bandwidth="384000" codecs="ac-3"/>
      <Representation id="aac" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
  </Period>''');

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
  final base = Uri.parse('https://cdn.example/film/manifest.mpd');

  group('a manifest', () {
    test('lists the picture best first and AAC sound before any other', () {
      final manifest = parseDashManifest(_numbered, base);

      expect(manifest.videos.map((video) => video.id), [
        'v1080',
        'v1080hevc',
        'v360',
      ]);
      expect(manifest.audio.map((sound) => sound.id), ['aac', 'ac3']);
      expect(manifest.videos.first.joinsAnywhere, isTrue);
      expect(manifest.byId('v1080hevc')!.joinsAnywhere, isFalse);
      expect(manifest.isLive, isFalse);
      expect(manifest.isProtected, isFalse);
      expect(manifest.duration, const Duration(seconds: 70, milliseconds: 500));
    });

    test('takes the sound of the language listed first', () {
      String language(String code, int bandwidth) =>
          '<AdaptationSet contentType="audio" lang="$code" mimeType="audio/mp4"'
          ' codecs="mp4a.40.2"><Representation id="$code" bandwidth="$bandwidth">'
          '<BaseURL>$code.mp4</BaseURL></Representation></AdaptationSet>';

      final manifest = parseDashManifest(
        _mpd(
          '<Period>${language('es', 96000)}${language('en', 128000)}</Period>',
        ),
        base,
      );

      // Not the louder bitrate of another language.
      expect(manifest.audio.map((sound) => sound.id), ['es', 'en']);
    });

    test('counts numbered segments from the length of the whole', () {
      final video = parseDashManifest(_numbered, base).byId('v360')!.media;

      // 70.5 seconds in 4-second segments.
      expect(video.segments, hasLength(18));
      expect(
        video.initialization!.url,
        'https://cdn.example/film/v360/init.mp4',
      );
      expect(
        video.segments.first.url,
        'https://cdn.example/film/v360/seg-00001.m4s',
      );
      expect(
        video.segments.last.url,
        'https://cdn.example/film/v360/seg-00018.m4s',
      );
      expect(video.isComplete, isTrue);
    });

    test('fills a timeline by time, repeats included', () {
      final manifest = parseDashManifest(
        _mpd('''
  <Period>
    <BaseURL>https://media.example/a/</BaseURL>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="v" bandwidth="900000" width="1280" height="720">
        <SegmentTemplate timescale="1000" initialization="init-\$Bandwidth\$.mp4"
            media="t\$Time\$-\$Number\$.m4s" startNumber="10">
          <SegmentTimeline>
            <S t="0" d="5000" r="2"/>
            <S d="2500"/>
          </SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>'''),
        base,
      );

      final media = manifest.videos.single.media;
      expect(
        media.initialization!.url,
        'https://media.example/a/init-900000.mp4',
      );
      expect(media.segments.map((segment) => segment.url), [
        'https://media.example/a/t0-10.m4s',
        'https://media.example/a/t5000-11.m4s',
        'https://media.example/a/t10000-12.m4s',
        'https://media.example/a/t15000-13.m4s',
      ]);
    });

    test('reads a written-out list with byte ranges', () {
      final manifest = parseDashManifest(
        _mpd('''
  <Period>
    <AdaptationSet contentType="video">
      <Representation id="v" bandwidth="1" mimeType="video/mp4">
        <BaseURL>one-file.mp4</BaseURL>
        <SegmentList>
          <Initialization range="0-899"/>
          <SegmentURL mediaRange="900-1999"/>
          <SegmentURL mediaRange="2000-2999"/>
        </SegmentList>
      </Representation>
    </AdaptationSet>
  </Period>'''),
        base,
      );

      final media = manifest.videos.single.media;
      expect(
        media.initialization!.url,
        'https://cdn.example/film/one-file.mp4',
      );
      expect(media.initialization!.range, (start: 0, length: 900));
      expect(media.segments.map((segment) => segment.range), [
        (start: 900, length: 1100),
        (start: 2000, length: 1000),
      ]);
    });

    test('takes a representation with no segment list as one file', () {
      final manifest = parseDashManifest(
        _mpd('''
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="v" bandwidth="1" width="640" height="360">
        <BaseURL>video-360.mp4</BaseURL>
        <SegmentBase indexRange="800-1200"/>
      </Representation>
    </AdaptationSet>
  </Period>'''),
        base,
      );

      final media = manifest.videos.single.media;
      expect(media.initialization, isNull);
      expect(
        media.segments.single.url,
        'https://cdn.example/film/video-360.mp4',
      );
      expect(media.segments.single.range, isNull);
    });

    test('says when it is live, protected, or cut into periods', () {
      final live = parseDashManifest(
        _numbered.replaceFirst('type="static"', 'type="dynamic"'),
        base,
      );
      expect(live.isLive, isTrue);
      expect(live.videos.first.media.isComplete, isFalse);

      final protected = parseDashManifest(
        _numbered.replaceFirst(
          '<SegmentTemplate timescale="1000"',
          '<ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-'
              '27dcd51d21ed"/><SegmentTemplate timescale="1000"',
        ),
        base,
      );
      expect(protected.isProtected, isTrue);

      final periods = parseDashManifest(
        _numbered.replaceFirst('</Period>', '</Period><Period></Period>'),
        base,
      );
      expect(periods.isSinglePeriod, isFalse);
    });

    test('that is not one is refused', () {
      expect(
        () => parseDashManifest('<html><body>Not found</body></html>', base),
        throwsFormatException,
      );
      expect(() => parseDashManifest('#EXTM3U', base), throwsFormatException);
    });
  });

  group('fetching a representation', () {
    late Directory workspace;

    setUp(() => workspace = Directory.systemTemp.createTempSync('dash_test'));
    tearDown(() => workspace.deleteSync(recursive: true));

    const manifestUrl = 'https://cdn.example/film/manifest.mpd';

    test('writes its header and segments end to end', () async {
      final into = File('${workspace.path}/audio.stream');
      final asked = <String>[];

      await fetchDashToFile(
        manifestUrl,
        'aac',
        into,
        concurrency: 3,
        client: MockClient((request) async {
          final url = request.url.toString();
          asked.add(url);
          if (url == manifestUrl) return http.Response(_numbered, 200);
          final name = url.split('/').last;
          return http.Response(name == 'init.mp4' ? 'H' : '<$name>', 200);
        }),
      );

      // 70.5 seconds in 4-second segments of sound.
      expect(into.readAsStringSync(), startsWith('H<1.m4s><2.m4s><3.m4s>'));
      expect(into.readAsStringSync(), endsWith('<18.m4s>'));
      expect(asked.where((url) => url.contains('/v')), isEmpty);
    });

    test('refuses a live and a protected stream', () async {
      MockClient serving(String manifest) =>
          MockClient((_) async => http.Response(manifest, 200));

      await expectLater(
        fetchDashToFile(
          manifestUrl,
          'aac',
          File('${workspace.path}/a.stream'),
          client: serving(
            _numbered.replaceFirst('type="static"', 'type="dynamic"'),
          ),
        ),
        _fetchFails(SlideshowFailureKind.streamLive),
      );
      await expectLater(
        fetchDashToFile(
          manifestUrl,
          'aac',
          File('${workspace.path}/a.stream'),
          client: serving(
            _numbered.replaceFirst(
              '<Representation id="aac"',
              '<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:'
                  '2011"/><Representation id="aac"',
            ),
          ),
        ),
        _fetchFails(SlideshowFailureKind.streamProtected),
      );
    });

    test('fails when the manifest no longer lists it', () async {
      await expectLater(
        fetchDashToFile(
          manifestUrl,
          'gone',
          File('${workspace.path}/a.stream'),
          client: MockClient((_) async => http.Response(_numbered, 200)),
        ),
        _fetchFails(SlideshowFailureKind.fetchFailed),
      );
    });
  });

  group('a link to a DASH stream', () {
    tearDown(ExtractorHttp.resetOverrides);

    const extractor = GenericExtractor(canJoinStreams: true);
    const manifestUrl = 'https://cdn.example/film/manifest.mpd';

    void serve(Map<String, String> bodies) {
      ExtractorHttp.getOverride = (uri, _) async {
        final body = bodies[uri.toString()];
        return body == null
            ? http.Response('', 404)
            : http.Response(
                body,
                200,
                headers: {
                  'content-type': body.contains('<MPD')
                      ? 'application/dash+xml'
                      : 'text/html; charset=utf-8',
                },
              );
      };
    }

    test(
      'offers one download per size, in the encoding every device takes',
      () async {
        serve({manifestUrl: _numbered});

        final result = await extractor.extract(manifestUrl);

        expect(result.qualities.map((option) => option.quality), [
          '1080p',
          '360p',
        ]);
        expect(result.duration, const Duration(seconds: 70, milliseconds: 500));
        final best = result.qualities.first.stream! as DashSource;
        expect(best.manifestUrl, manifestUrl);
        expect(best.videoId, 'v1080');
        expect(best.audioId, 'aac');
        expect(result.qualities.first.previewUrl, manifestUrl);
      },
    );

    test('is found in the script of a page that declares no file', () async {
      const page = 'https://video.example/watch/7';
      serve({
        page:
            '<html><head><title>Film</title></head><body><script>'
            r'player.load("https:\/\/cdn.example\/film\/manifest.mpd");'
            '</script></body></html>',
        manifestUrl: _numbered,
      });

      final result = await extractor.extract(page);

      expect(result.title, 'Film');
      expect(result.qualities.first.stream, isA<DashSource>());
    });

    test(
      'says when the stream is live, protected, or in several parts',
      () async {
        serve({
          'https://cdn.example/live.mpd': _numbered.replaceFirst(
            'type="static"',
            'type="dynamic"',
          ),
          'https://cdn.example/locked.mpd': _numbered.replaceFirst(
            '<Representation id="aac"',
            '<ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011"/>'
                '<Representation id="aac"',
          ),
          'https://cdn.example/parts.mpd': _numbered.replaceFirst(
            '</Period>',
            '</Period><Period></Period>',
          ),
        });

        await expectLater(
          extractor.extract('https://cdn.example/live.mpd'),
          _extractionFails(ExtractionFailureKind.genericStreamLive),
        );
        await expectLater(
          extractor.extract('https://cdn.example/locked.mpd'),
          _extractionFails(ExtractionFailureKind.genericStreamProtected),
        );
        await expectLater(
          extractor.extract('https://cdn.example/parts.mpd'),
          _extractionFails(ExtractionFailureKind.genericStreamOnly),
        );
      },
    );

    test('is reported as a stream where it cannot be joined', () async {
      serve({manifestUrl: _numbered});

      await expectLater(
        const GenericExtractor(canJoinStreams: false).extract(manifestUrl),
        _extractionFails(ExtractionFailureKind.genericStreamOnly),
      );
    });
  });
}
