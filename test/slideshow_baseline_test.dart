import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/core/utils/quality_helper.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/services/extractors/tiktok_extractor.dart';

import 'extractor_fixture_test.dart' show fixture;

/// The behaviour a TikTok photo post has today, recorded so the slideshow
/// feature can prove it did not change it.
void main() {
  tearDown(ExtractorHttp.resetOverrides);

  Future<void> withPhotoPost(void Function(VideoMetadata result) check) async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);
    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
    );
    check(result);
  }

  test('a photo post still defaults to an image, not a video', () async {
    await withPhotoPost((result) {
      expect(
        QualityHelper.bestMatch(result.qualities, 'Highest')!.isImage,
        isTrue,
      );
      expect(result.bestQuality!.isImage, isTrue);
    });
  });

  test('a photo post still lists its images in source order', () async {
    await withPhotoPost((result) {
      final images = result.qualities.where((o) => o.isImage).toList();
      expect(images, hasLength(2));
      expect(images.first.downloadUrl, endsWith('/tiktok/image-1.jpg'));
      expect(images.last.downloadUrl, endsWith('/images/image-2.webp'));
    });
  });

  test('a photo post still exposes exactly one audio option', () async {
    await withPhotoPost((result) {
      expect(result.qualities.where((o) => o.isAudioOnly), hasLength(1));
    });
  });
}
