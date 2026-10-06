import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/generic_extractor.dart';

const _pageUrl = 'https://blog.example.test/posts/42';

Future<VideoMetadata> _read(String html) {
  ExtractorHttp.getOverride = (_, _) async => http.Response(
    '<!doctype html><html><head><title>A page</title></head>$html</html>',
    200,
    headers: {'content-type': 'text/html; charset=utf-8'},
  );
  return const GenericExtractor().extract(_pageUrl);
}

Matcher _failsWith(ExtractionFailureKind kind) => throwsA(
  isA<ExtractionException>().having(
    (error) => error.failure.kind,
    'failure kind',
    kind,
  ),
);

List<String> _urls(VideoMetadata result, MediaKind kind) => [
  for (final option in result.qualities)
    if (option.kind == kind) option.downloadUrl,
];

void main() {
  tearDown(ExtractorHttp.resetOverrides);

  test('a <video> element is found, with its poster as the cover', () async {
    final result = await _read(
      '<body><video controls poster="/img/poster.jpg" src="/media/clip.mp4">'
      '</video></body>',
    );

    expect(_urls(result, MediaKind.video), [
      'https://blog.example.test/media/clip.mp4',
    ]);
    expect(result.qualities.single.label, isA<EmbeddedVideo>());
    expect(result.coverUrl, 'https://blog.example.test/img/poster.jpg');
    expect(result.title, 'A page');
  });

  test('the sources of one element are one clip, MP4 preferred', () async {
    final result = await _read(
      '<body><video><source src="clip.webm" type="video/webm">'
      "<source src='clip.mp4' type='video/mp4'></video></body>",
    );

    expect(_urls(result, MediaKind.video), [
      'https://blog.example.test/posts/clip.mp4',
    ]);
    expect(result.qualities.single.format, 'mp4');
  });

  test('two elements are two clips, each its own download', () async {
    final result = await _read(
      '<body><video src="https://cdn.example.test/one.mp4"></video>'
      '<video src="//cdn.example.test/two.webm"></video></body>',
    );

    expect(_urls(result, MediaKind.video), [
      'https://cdn.example.test/one.mp4',
      'https://cdn.example.test/two.webm',
    ]);
    expect(result.qualities.map((option) => option.label), [
      isA<VideoIndex>(),
      isA<VideoIndex>(),
    ]);
    expect(
      result.qualities.map((option) => option.mediaId).toSet(),
      hasLength(2),
    );
    expect(result.qualities.last.format, 'webm');
  });

  test('a video named twice is offered once', () async {
    final result = await _read(
      '<head><meta property="og:video" content="/media/clip.mp4">'
      '<meta property="og:image" content="/img/cover.jpg"></head>'
      '<body><video src="/media/clip.mp4"></video></body>',
    );

    expect(_urls(result, MediaKind.video), hasLength(1));
    // With a video on the page the picture is its poster, not a download.
    expect(_urls(result, MediaKind.image), isEmpty);
    expect(result.coverUrl, 'https://blog.example.test/img/cover.jpg');
  });

  test('JSON-LD media objects are read, decoration is not', () async {
    final result = await _read('''
<head><script type="application/ld+json">
{"@context":"https://schema.org","@graph":[
  {"@type":"Article","image":"https://cdn.example.test/hero.jpg",
   "publisher":{"@type":"Organization","logo":{"@type":"ImageObject","url":"https://cdn.example.test/logo.png"}}},
  {"@type":"VideoObject","name":"A talk","contentUrl":"https://cdn.example.test/talk.mp4"}
]}
</script></head>''');

    expect(_urls(result, MediaKind.video), [
      'https://cdn.example.test/talk.mp4',
    ]);
    expect(_urls(result, MediaKind.image), isEmpty);
  });

  test('a gallery lists every og:image as its own picture', () async {
    final result = await _read(
      '<head><meta property="og:image" content="/img/1.jpg">'
      '<meta content="/img/2.png" property="og:image">'
      '<meta property="og:image" content="/img/1.jpg"></head>',
    );

    expect(_urls(result, MediaKind.image), [
      'https://blog.example.test/img/1.jpg',
      'https://blog.example.test/img/2.png',
    ]);
    expect(
      result.qualities.map((option) => (option.label as ImageIndex).index),
      [1, 2],
    );
    expect(
      result.qualities.map((option) => option.mediaId).toSet(),
      hasLength(2),
    );
  });

  test('audio is found in a tag and in Open Graph', () async {
    final tagged = await _read(
      '<body><audio controls><source src="/audio/episode.mp3"></audio></body>',
    );
    expect(_urls(tagged, MediaKind.audio), [
      'https://blog.example.test/audio/episode.mp3',
    ]);
    expect(tagged.qualities.single.format, 'mp3');

    final declared = await _read(
      '<head><meta property="og:audio" content="/audio/track.m4a"></head>',
    );
    expect(_urls(declared, MediaKind.audio), [
      'https://blog.example.test/audio/track.m4a',
    ]);
  });

  test('addresses that only exist inside the page are ignored', () async {
    await expectLater(
      _read(
        '<body><video src="blob:https://blog.example.test/1b2c"></video>'
        '<video src="data:video/mp4;base64,AAAA"></video></body>',
      ),
      _failsWith(ExtractionFailureKind.genericNoVideo),
    );
  });

  test('a page that only streams says so', () async {
    await expectLater(
      _read(
        '<head><meta property="og:video" content="/hls/master.m3u8"></head>'
        '<body><video><source src="/dash/manifest.mpd"></video></body>',
      ),
      _failsWith(ExtractionFailureKind.genericStreamOnly),
    );
  });

  test('a stream next to a file falls back to the file', () async {
    final result = await _read(
      '<body><video><source src="/hls/master.m3u8">'
      '<source src="/media/clip.mp4"></video></body>',
    );

    expect(_urls(result, MediaKind.video), [
      'https://blog.example.test/media/clip.mp4',
    ]);
  });

  test('a page with no media reports that nothing was found', () async {
    await expectLater(
      _read('<body><p>Words only.</p></body>'),
      _failsWith(ExtractionFailureKind.genericNoVideo),
    );
  });
}
