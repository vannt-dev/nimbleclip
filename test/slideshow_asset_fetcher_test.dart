import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/services/slideshow/slideshow_asset_fetcher.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('slideshow_test'));
  tearDown(() {
    ExtractorHttp.resetOverrides();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('images land on disk in source order', () async {
    ExtractorHttp.getOverride = (uri, _) async =>
        http.Response.bytes([1, 2, 3], 200);

    final assets = await fetchSlideshowAssets(
      const SlideshowSource(
        imageUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg'],
      ),
      into: temp,
    );

    expect(assets.imagePaths, hasLength(2));
    expect(File(assets.imagePaths.first).readAsBytesSync(), [1, 2, 3]);
    expect(assets.imagePaths.first, endsWith('image_0.jpg'));
    expect(assets.imagePaths.last, endsWith('image_1.jpg'));
    expect(assets.audioPath, isNull);
  });

  test('a failed audio fetch does not fail the whole render', () async {
    ExtractorHttp.getOverride = (uri, _) async => uri.path.endsWith('.mp3')
        ? http.Response('nope', 500)
        : http.Response.bytes([1], 200);

    final assets = await fetchSlideshowAssets(
      const SlideshowSource(
        imageUrls: ['https://cdn/a.jpg'],
        audioUrl: 'https://cdn/song.mp3',
      ),
      into: temp,
    );

    expect(assets.imagePaths, hasLength(1));
    expect(assets.audioPath, isNull);
  });

  test('a failed image fetch does fail the render', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response('nope', 404);

    await expectLater(
      fetchSlideshowAssets(
        const SlideshowSource(imageUrls: ['https://cdn/a.jpg']),
        into: temp,
      ),
      throwsA(
        isA<SlideshowException>().having(
          (e) => e.kind,
          'kind',
          SlideshowFailureKind.fetchFailed,
        ),
      ),
    );
  });

  test('an empty source is rejected before any request', () async {
    await expectLater(
      fetchSlideshowAssets(const SlideshowSource(imageUrls: []), into: temp),
      throwsA(
        isA<SlideshowException>().having(
          (e) => e.kind,
          'kind',
          SlideshowFailureKind.noImages,
        ),
      ),
    );
  });
}
