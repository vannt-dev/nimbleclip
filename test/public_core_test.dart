import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/extractors_public/base_extractor.dart';
import 'package:nimble_clip/services/extractors_public/extraction_failure.dart';
import 'package:nimble_clip/services/extractors_public/registry.dart';
import 'package:nimble_clip/services/extractors_public/youtube_playlist.dart';

/// The public core: what a checkout without the private one is built with.
void main() {
  final registry = ExtractorRegistry();

  tearDown(ExtractorHttp.resetOverrides);

  void serve(String body, {int status = 200, String type = 'text/html'}) {
    ExtractorHttp.getOverride = (_, _) async => http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': type},
    );
  }

  Matcher fails(ExtractionFailureKind kind) => throwsA(
    isA<ExtractionException>().having((e) => e.failure.kind, 'kind', kind),
  );

  test(
    'a link to a media file is offered as it is, without a request',
    () async {
      ExtractorHttp.getOverride = (_, _) async => fail('no page is needed');

      final video = await registry.extract(
        'https://cdn.example.com/clips/demo%20one.mp4?x=1',
      );
      expect(video.platform, VideoPlatform.generic);
      expect(video.title, 'demo one.mp4');
      expect(video.qualities.single.kind, MediaKind.video);
      expect(video.qualities.single.format, 'mp4');
      expect(
        video.qualities.single.downloadUrl,
        'https://cdn.example.com/clips/demo%20one.mp4?x=1',
      );

      final song = await registry.extract('https://cdn.example.com/a/song.MP3');
      expect(song.qualities.single.kind, MediaKind.audio);
      expect(song.qualities.single.format, 'mp3');

      final picture = await registry.extract('https://cdn.example.com/p.webp');
      expect(picture.qualities.single.kind, MediaKind.image);
      expect(picture.coverUrl, 'https://cdn.example.com/p.webp');
    },
  );

  test('a page names its video in Open Graph metadata', () async {
    serve('''
<html><head><title>Fallback title</title>
<meta property="og:title" content="A clip &amp; a half">
<meta property="og:site_name" content="Example Videos">
<meta property="og:image" content="/posters/1.jpg">
<meta property="og:video" content="http://cdn.example.com/1.mp4">
<meta property="og:video:secure_url" content="https://cdn.example.com/1.mp4">
</head></html>''');

    final result = await registry.extract('https://example.com/watch/1');
    expect(result.title, 'A clip & a half');
    expect(result.author, 'Example Videos');
    expect(result.coverUrl, 'https://example.com/posters/1.jpg');
    // the secure address is preferred, and the poster is not a second download
    expect(
      result.qualities.single.downloadUrl,
      'https://cdn.example.com/1.mp4',
    );
    expect(result.qualities.single.kind, MediaKind.video);
  });

  test('a page with only a picture offers the picture', () async {
    serve(
      '<meta name="twitter:image" content="https://img.example.com/a.png">',
    );

    final result = await registry.extract('https://example.com/post/2');
    expect(result.qualities.single.kind, MediaKind.image);
    expect(result.qualities.single.format, 'png');
    expect(result.title, 'example.com');
  });

  test(
    'a file served from an address without an extension is read by its type',
    () async {
      serve('', type: 'video/mp4');

      final result = await registry.extract(
        'https://example.com/download?id=7',
      );
      expect(result.qualities.single.kind, MediaKind.video);
      expect(result.qualities.single.format, 'mp4');
    },
  );

  test('what it cannot read is said plainly', () async {
    serve('<html><body><div id="player"></div></body></html>');
    await expectLater(
      registry.extract('https://example.com/app'),
      fails(ExtractionFailureKind.genericNoVideo),
    );

    // a stream is not a file, and this core follows none
    serve(
      '<meta property="og:video" content="https://cdn.example.com/live.m3u8">',
    );
    await expectLater(
      registry.extract('https://example.com/stream'),
      fails(ExtractionFailureKind.genericNoVideo),
    );

    serve('gone', status: 404);
    await expectLater(
      registry.extract('https://example.com/missing'),
      fails(ExtractionFailureKind.linkAccessFailed),
    );

    ExtractorHttp.getOverride = (_, _) async =>
        throw http.ClientException('offline');
    await expectLater(
      registry.extract('https://example.com/offline'),
      fails(ExtractionFailureKind.linkAccessFailed),
    );

    await expectLater(
      registry.extract('not a link'),
      fails(ExtractionFailureKind.invalidLink),
    );
  });

  test('a player page named as the video is not offered as a file', () async {
    serve('''
<meta property="og:video" content="https://player.example.com/embed/9">
<meta property="og:video:type" content="text/html">
<meta property="og:image" content="https://img.example.com/9.jpg">''');
    final result = await registry.extract('https://example.com/watch/9');
    expect(result.qualities.single.kind, MediaKind.image);

    // without an extension, the type the page declares decides
    serve('''
<meta property="og:video" content="https://cdn.example.com/file?id=9">
<meta property="og:video:type" content="video/mp4">''');
    final declared = await registry.extract('https://example.com/watch/10');
    expect(declared.qualities.single.kind, MediaKind.video);
    expect(declared.qualities.single.format, 'mp4');
  });

  test('a site the full core reads by name is not treated as a page', () async {
    ExtractorHttp.getOverride = (_, _) async => fail('the page is not fetched');
    for (final link in const [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://www.tiktok.com/@someone/video/1',
    ]) {
      await expectLater(
        registry.extract(link),
        fails(ExtractionFailureKind.noDownloadStreams),
      );
    }
  });

  test('a playlist link is not taken for one', () async {
    const link = 'https://www.youtube.com/playlist?list=PL123';
    expect(youtubePlaylistIdFrom(link), isNull);
    await expectLater(
      const YouTubePlaylistReader().read(link),
      fails(ExtractionFailureKind.youtubePlaylistUnavailable),
    );
  });
}
