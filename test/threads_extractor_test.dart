import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/constants/app_constants.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/core/utils/url_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/extractors/threads_extractor.dart';

String fixture(String name) =>
    File('test/fixtures/extractors/$name').readAsStringSync();

Matcher failsWith(ExtractionFailureKind kind) => throwsA(
  isA<ExtractionException>().having(
    (error) => error.failure.kind,
    'failure kind',
    kind,
  ),
);

void main() {
  tearDown(ExtractorHttp.resetOverrides);

  test('both Threads domains route to the Threads extractor', () {
    for (final url in [
      'https://www.threads.net/@someone/post/VIDEOcode01',
      'https://www.threads.com/@someone/post/VIDEOcode01?xmt=tracking',
      'https://threads.com/t/VIDEOcode01',
    ]) {
      expect(UrlHelper.detectPlatform(url), VideoPlatform.threads);
      expect(ExtractorRegistry().getExtractorFor(url), isA<ThreadsExtractor>());
      expect(ThreadsExtractor.postCodeOf(url), 'VIDEOcode01');
    }
  });

  test('a video post yields its video, and ignores the replies', () async {
    Uri? requested;
    Map<String, String>? sent;
    ExtractorHttp.getOverride = (uri, headers) async {
      requested = uri;
      sent = headers;
      return http.Response(fixture('threads_video.html'), 200);
    };

    final result = await const ThreadsExtractor().extract(
      'https://www.threads.net/@space_agency/post/VIDEOcode01?xmt=tracking',
    );

    expect(result.platform, VideoPlatform.threads);
    expect(result.id, 'VIDEOcode01');
    expect(result.author, 'space_agency');
    expect(result.title, 'Next stop: the station');
    expect(result.likeCount, 1234);
    expect(result.qualities, hasLength(1));

    final video = result.qualities.single;
    expect(video.isImage, isFalse);
    expect(video.label, isA<OriginalMp4>());
    expect(video.format, 'mp4');
    expect(video.downloadUrl, contains('.mp4'));
    // The widest still, not the first one listed.
    expect(video.thumbnailUrl, result.coverUrl);
    expect(result.coverUrl, contains('.jpg'));

    // Threads only includes the post for a search crawler, and the tracking
    // parameters are not sent along.
    expect(sent!.values, contains(AppConstants.searchCrawlerUserAgent));
    expect(requested!.hasQuery, isFalse);
    expect(requested!.path, '/@space_agency/post/VIDEOcode01');
  });

  test('a mixed carousel keeps every picture and video, video first', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('threads_carousel.html'), 200);

    final result = await const ThreadsExtractor().extract(
      'https://www.threads.com/@space_agency/post/MIXEDcode01',
    );

    final videos = result.qualities.where((option) => !option.isImage).toList();
    final pictures = result.qualities
        .where((option) => option.isImage)
        .toList();
    expect(videos, hasLength(1));
    expect(pictures, hasLength(2));
    expect(pictures.map((option) => (option.label as ImageIndex).index), [
      1,
      2,
    ]);
    // Each item is its own download, not a quality of one video.
    expect(
      result.qualities.map((option) => option.mediaId).toSet(),
      hasLength(3),
    );
    expect(result.bestQuality!.isImage, isFalse);
  });

  test('a text-only post reports that it has no media', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('threads_text.html'), 200);

    await expectLater(
      const ThreadsExtractor().extract(
        'https://www.threads.com/@a_writer/post/TEXTcode001',
      ),
      failsWith(ExtractionFailureKind.threadsNoMedia),
    );
  });

  test(
    'a short link is asked for again under the address the page names',
    () async {
      final requested = <String>[];
      ExtractorHttp.getOverride = (uri, _) async {
        requested.add(uri.path);
        // What a redirected request gets: the shell, with the post's own
        // address in it but none of its media.
        return uri.path.startsWith('/t/')
            ? http.Response(
                '<link rel="canonical" href="https://www.threads.com/'
                '&#064;space_agency/post/VIDEOcode01" />',
                200,
              )
            : http.Response(fixture('threads_video.html'), 200);
      };

      final result = await const ThreadsExtractor().extract(
        'https://www.threads.net/t/VIDEOcode01',
      );

      expect(requested, ['/t/VIDEOcode01', '/@space_agency/post/VIDEOcode01']);
      expect(result.qualities.single.downloadUrl, contains('.mp4'));
    },
  );

  test('a page without the post reports that it has no media', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('threads_video.html'), 200);

    await expectLater(
      const ThreadsExtractor().extract(
        'https://www.threads.com/@space_agency/post/SomeOtherCode',
      ),
      failsWith(ExtractionFailureKind.threadsNoMedia),
    );
  });

  test('a refused page reports that it has no media', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response('', 404);

    await expectLater(
      const ThreadsExtractor().extract(
        'https://www.threads.com/@space_agency/post/VIDEOcode01',
      ),
      failsWith(ExtractionFailureKind.threadsNoMedia),
    );
  });

  test('a profile link is not a post', () async {
    await expectLater(
      const ThreadsExtractor().extract('https://www.threads.com/@space_agency'),
      failsWith(ExtractionFailureKind.threadsInvalidPost),
    );
  });
}
