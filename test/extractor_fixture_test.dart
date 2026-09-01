import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/core/utils/quality_helper.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/core/utils/external_service_policy.dart';
import 'package:nimble_clip/models/gallery_notice.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/facebook_extractor.dart';
import 'package:nimble_clip/services/extractors/generic_extractor.dart';
import 'package:nimble_clip/services/extractors/instagram_extractor.dart';
import 'package:nimble_clip/services/extractors/tiktok_extractor.dart';
import 'package:nimble_clip/services/extractors/twitter_extractor.dart';
import 'package:nimble_clip/services/extractors/youtube_extractor.dart';

/// A post holding both photos and video must default to the video.
///
/// Regression: `VideoQualityOption.image` leaves `quality` at 'Original',
/// which the named-height table reads as 2160. Every photo therefore outranked
/// every video, the default selection landed on a photo, and the video tab —
/// which lists video options only — showed nothing selected.
void _expectDefaultSelectionIsVideo(VideoMetadata result) {
  expect(result.qualities.any((option) => option.isImage), isTrue);
  expect(
    QualityHelper.bestMatch(result.qualities, 'Highest')!.isImage,
    isFalse,
  );
  expect(result.bestQuality!.isImage, isFalse);
}

String fixture(String name) =>
    File('test/fixtures/extractors/$name').readAsStringSync();

void main() {
  tearDown(() {
    ExtractorHttp.resetOverrides();
  });

  test('external-only extractors respect the privacy policy', () async {
    await expectLater(
      const TikTokExtractor(
        externalServiceAccess: FixedExternalServiceAccess(false),
      ).extract('https://www.tiktok.com/@u/video/1'),
      throwsA(
        // Asserted on identity, not on wording. The previous version checked
        // that the text contained "disabled", which the new `toString()` also
        // satisfies — it would have stayed green while testing nothing.
        isA<ExtractionException>().having(
          (error) => error.failure.kind,
          'failure kind',
          ExtractionFailureKind.externalServicesDisabled,
        ),
      ),
    );
  });

  test('TikTok parses the API fixture', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/video/1',
    );

    expect(result.platform, VideoPlatform.tiktok);
    expect(result.title, 'TikTok fixture');
    expect(result.qualities, hasLength(2));
    expect(result.qualities.first.downloadUrl, endsWith('/video/hd.mp4'));
    // Asserted on the descriptor, not on rendered text: the layer no longer
    // produces wording, so a locale change cannot move this test.
    expect(
      result.qualities.first.label,
      isA<WatermarkedVideo>()
          .having((label) => label.quality, 'quality', 'HD 1080p')
          .having((label) => label.watermarked, 'watermarked', isFalse),
    );
  });

  test('TikTok exposes every slideshow image as a download option', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
    );

    final images = result.qualities.where((option) => option.isImage).toList();
    expect(images, hasLength(2));
    expect(images.first.format, 'jpg');
    expect(images.last.downloadUrl, endsWith('/images/image-2.webp'));
    expect(images.last.format, 'webp');
    expect(images.map((option) => (option.label as ImageIndex).index), [1, 2]);
  });

  test('X parses and sorts the FxTwitter fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('twitter.json'), 200);

    final result = await const TwitterExtractor().extract(
      'https://x.com/fixture/status/123456789',
    );

    expect(result.platform, VideoPlatform.twitter);
    expect(result.author, 'Fixture User');
    expect(result.qualities.first.quality, '720p');
    expect(result.qualities, hasLength(2));
    // X names its variants by bitrate rather than by resolution alone.
    expect(
      result.qualities.first.label,
      isA<VideoBitrate>().having((label) => label.quality, 'quality', '720p'),
    );
  });

  test('X exposes videos and photos from the same post', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('twitter_mixed.json'), 200);

    final result = await const TwitterExtractor().extract(
      'https://x.com/fixture/status/987654321',
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(result.qualities.where((option) => !option.isImage), hasLength(1));
    _expectDefaultSelectionIsVideo(result);
  });

  test('Facebook parses playable URLs from a page fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/watch/?v=123456',
    );

    expect(result.platform, VideoPlatform.facebook);
    expect(result.id, '123456');
    expect(result.title, 'Facebook Fixture');
    expect(result.qualities, hasLength(2));
  });

  test('Facebook resolves a share Reel before extracting its video', () async {
    final requestedPaths = <String>[];
    ExtractorHttp.getOverride = (uri, _) async {
      requestedPaths.add(uri.path);
      if (uri.path == '/share/r/1DoJYK37gr/') {
        return http.Response(
          '',
          200,
          request: http.Request(
            'GET',
            Uri.parse('https://www.facebook.com/reel/123456/'),
          ),
        );
      }
      return http.Response(fixture('facebook.html'), 200);
    };

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/share/r/1DoJYK37gr/',
    );

    expect(requestedPaths, ['/share/r/1DoJYK37gr/', '/reel/123456/']);
    expect(result.originalUrl, 'https://www.facebook.com/reel/123456/');
    expect(result.qualities.every((option) => !option.isImage), isTrue);
  });

  // Expanding a share link already downloads the page it points at, and the
  // first extraction strategy then asked for that very same URL again — two
  // full page downloads to read one page. The redirect above keeps its second
  // request because the response modelling it carries no body; a response that
  // does carry one is used as it stands.
  test('Facebook reuses the page the share link already fetched', () async {
    final requestedPaths = <String>[];
    ExtractorHttp.getOverride = (uri, _) async {
      requestedPaths.add(uri.path);
      if (uri.path == '/share/r/Reuse/') {
        return http.Response(
          fixture('facebook.html'),
          200,
          request: http.Request(
            'GET',
            Uri.parse('https://www.facebook.com/reel/999999/'),
          ),
        );
      }
      return http.Response(fixture('facebook.html'), 200);
    };

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/share/r/Reuse/',
    );

    expect(requestedPaths, ['/share/r/Reuse/']);
    expect(result.originalUrl, 'https://www.facebook.com/reel/999999/');
    expect(result.qualities, hasLength(2));
  });

  test(
    'Facebook reads an Open Graph video from a share landing page',
    () async {
      var shareRequests = 0;
      ExtractorHttp.getOverride = (uri, _) async {
        if (uri.path == '/share/r/ShareToken/') {
          shareRequests++;
          // The first request models a share URL whose redirect is opaque. The
          // second is the landing page fetched by the extractor itself.
          if (shareRequests == 1) return http.Response('', 200);
          return http.Response('''
          <html><head>
            <meta content="/media/reel.mp4" property="og:video:url">
            <meta property="og:image" content="https://cdn.example/poster.jpg">
          </head></html>
        ''', 200);
        }
        return http.Response('', 404);
      };

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/share/r/ShareToken/',
      );

      expect(result.qualities, hasLength(1));
      expect(shareRequests, 2);
      expect(result.qualities.single.kind, MediaKind.video);
      expect(
        result.qualities.single.downloadUrl,
        'https://www.facebook.com/media/reel.mp4',
      );
    },
  );

  test(
    'Facebook keeps looking when the watch page only exposes a poster',
    () async {
      var requestCount = 0;
      ExtractorHttp.getOverride = (uri, _) async {
        requestCount++;
        if (uri.path == '/plugins/video.php') {
          return http.Response(fixture('facebook.html'), 200);
        }
        return http.Response(fixture('facebook_image.html'), 200);
      };

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/example/videos/123456/',
      );

      expect(requestCount, 2);
      expect(result.qualities, hasLength(2));
      expect(result.qualities.every((option) => !option.isImage), isTrue);
    },
  );

  test('Facebook exposes a public photo post', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_image.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/photo/?fbid=654321',
    );

    expect(result.qualities, hasLength(1));
    expect(result.qualities.single.isImage, isTrue);
    expect(result.qualities.single.format, 'webp');
  });

  test('Facebook exposes every photo in a public carousel', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_carousel.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/example/posts/654321',
    );

    expect(result.qualities, hasLength(2));
    expect(result.qualities.every((option) => option.isImage), isTrue);
    expect(
      result.qualities.first.downloadUrl,
      'https://cdn.example/facebook-full-1.jpg',
    );
    expect(result.qualities.last.format, 'webp');
    expect(result.coverUrl, isNot('https://cdn.example/facebook-poster.jpg'));
  });

  test(
    'Facebook keeps the richest image result across page strategies',
    () async {
      var calls = 0;
      ExtractorHttp.getOverride = (_, _) async {
        calls++;
        return http.Response(
          fixture(
            calls == 1 ? 'facebook_image.html' : 'facebook_carousel.html',
          ),
          200,
        );
      };

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/example/posts/richest',
      );

      expect(result.qualities.where((option) => option.isImage), hasLength(2));
    },
  );

  test(
    'Facebook falls back to every public post photo and removes avatars',
    () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('facebook_image.html'), 200);
      ExtractorHttp.postOverride = (_, _, _) async =>
          http.Response(fixture('facebook_fallback.json'), 200);

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/cebuanafinance/posts/662287040177856/',
      );

      final images = result.qualities
          .where((option) => option.isImage)
          .toList();
      expect(images, hasLength(4));
      expect(
        images.every((option) => !option.downloadUrl.contains('avatar')),
        isTrue,
      );
      expect(result.coverUrl, images.first.downloadUrl);
    },
  );

  test('Facebook reads a shared album link that never redirects', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_image.html'), 200);
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('facebook_fallback.json'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/share/1CYGwgPahk/',
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(4));
  });

  test('Facebook reads a group post permalink album', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_image.html'), 200);
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('facebook_fallback.json'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/groups/1234567890/permalink/9876543210/',
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(4));
  });

  group('Facebook gallery notice', () {
    test('says so when external services are off', () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('facebook_image.html'), 200);

      final result = await const FacebookExtractor(
        externalServiceAccess: FixedExternalServiceAccess(false),
      ).extract('https://www.facebook.com/example/posts/654321');

      expect(result.galleryNotice, GalleryNotice.externalServicesDisabled);
      expect(result.qualities.where((option) => option.isImage), hasLength(1));
    });

    test('says so when the service does not answer', () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('facebook_image.html'), 200);
      ExtractorHttp.postOverride = (_, _, _) async =>
          http.Response('upstream exploded', 503);

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/example/posts/654321',
      );

      expect(result.galleryNotice, GalleryNotice.galleryCheckUnavailable);
      expect(result.qualities.where((option) => option.isImage), hasLength(1));
    });

    test('stays quiet when the post really holds one photo', () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('facebook_image.html'), 200);
      ExtractorHttp.postOverride = (_, _, _) async =>
          http.Response('{"images":[]}', 200);

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/example/posts/654321',
      );

      expect(result.galleryNotice, isNull);
    });

    test('stays quiet when the gallery was read in full', () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('facebook_image.html'), 200);
      ExtractorHttp.postOverride = (_, _, _) async =>
          http.Response(fixture('facebook_fallback.json'), 200);

      final result = await const FacebookExtractor().extract(
        'https://www.facebook.com/example/posts/654321',
      );

      expect(result.galleryNotice, isNull);
      expect(result.qualities.where((option) => option.isImage), hasLength(4));
    });
  });

  test('Facebook keeps video and photos from a mixed public post', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_mixed.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/example/posts/mixed123',
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(
      result.qualities.where(
        (option) => !option.isImage && !option.isAudioOnly,
      ),
      hasLength(1),
    );
    _expectDefaultSelectionIsVideo(result);
  });

  test('Instagram parses a public embed fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('instagram.html'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/reel/fixture123/',
    );

    expect(result.platform, VideoPlatform.instagram);
    expect(result.author, 'fixture_user');
    expect(result.qualities.single.downloadUrl, 'https://cdn.example/ig.mp4');
  });

  test('Instagram exposes every carousel image as a download option', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('instagram_images.html'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/p/imageFixture/',
    );

    expect(result.author, 'fixture_photographer');
    expect(result.qualities, hasLength(2));
    expect(result.qualities.every((option) => option.isImage), isTrue);
    expect(result.qualities.last.downloadUrl, 'https://cdn.example/ig-2.webp');
  });

  test('Instagram keeps video and images from a mixed carousel', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('instagram_mixed.html'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/p/mixedFixture/',
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(
      result.qualities.where(
        (option) => !option.isImage && !option.isAudioOnly,
      ),
      hasLength(1),
    );
    _expectDefaultSelectionIsVideo(result);
  });

  test(
    'Instagram enriches an og:image with SnapInsta carousel slides',
    () async {
      ExtractorHttp.getOverride = (uri, _) async {
        if (uri.host == 'snap-insta.to') {
          return http.Response(fixture('snapinsta_page.html'), 200);
        }
        return http.Response(fixture('instagram_single_image.html'), 200);
      };
      ExtractorHttp.postOverride = (uri, _, body) async {
        expect(uri.host, 'snap-insta.to');
        expect(body, containsPair('k_token', 'fixture-token'));
        expect(
          body,
          containsPair('q', 'https://www.instagram.com/p/carousel/'),
        );
        return http.Response(fixture('snapinsta_carousel.json'), 200);
      };

      final result = await const InstagramExtractor().extract(
        'https://www.instagram.com/p/carousel/',
      );

      expect(result.qualities, hasLength(2));
      expect(result.qualities.every((option) => option.isImage), isTrue);
      expect(
        result.qualities.first.downloadUrl,
        'https://dl.snapcdn.app/get?token=download-one',
      );
      expect(result.coverUrl, 'https://i.snapcdn.app/photo?token=preview-one');
    },
  );

  test('Instagram reads a highlight link, video and photos alike', () async {
    // A highlight has no post shortcode, so the direct embed and post-page
    // strategies cannot apply; the page itself is a JavaScript shell behind a
    // login wall. The fallback service is the only route.
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('snapinsta_page.html'), 200);
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('snapinsta_story.json'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/s/aGlnaGxpZ2h0OjE3OTUyMDE2NTI2OTUyMjAx'
      '?story_media_id=3338279895419090365_15710939660',
    );

    expect(result.platform, VideoPlatform.instagram);
    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(result.qualities.where((option) => !option.isImage), hasLength(2));
    // A highlight carries many videos. Labelling each one "MP4 (Original
    // quality)" leaves a column of identical rows with no way to tell them
    // apart; photos have always been numbered.
    expect(
      result.qualities
          .where((option) => !option.isImage)
          .map((option) => (option.label as VideoIndex).index),
      [1, 2],
    );
    _expectDefaultSelectionIsVideo(result);
  });

  test('Instagram reads a story link', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('snapinsta_page.html'), 200);
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('snapinsta_story.json'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/stories/someone/3338279895419090365/',
    );

    expect(result.qualities, hasLength(4));
  });

  test('a highlight says so when external services are off', () async {
    // Without the fallback there is no other route, so this must report the
    // real reason rather than the "that is not an Instagram post" message.
    await expectLater(
      const InstagramExtractor(
        externalServiceAccess: FixedExternalServiceAccess(false),
      ).extract(
        'https://www.instagram.com/s/aGlnaGxpZ2h0OjE3OTUyMDE2NTI2OTUyMjAx',
      ),
      throwsA(
        isA<ExtractionException>().having(
          (error) => error.failure.kind,
          'failure kind',
          ExtractionFailureKind.externalServicesDisabled,
        ),
      ),
    );
  });

  test('Instagram classifies a SnapInsta Reel result as video', () async {
    ExtractorHttp.getOverride = (uri, _) async {
      if (uri.host == 'snap-insta.to') {
        return http.Response(fixture('snapinsta_page.html'), 200);
      }
      return http.Response(fixture('instagram_single_image.html'), 200);
    };
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('snapinsta_video.json'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/reel/videoFixture/',
    );

    expect(result.qualities, hasLength(1));
    expect(result.qualities.single.kind, MediaKind.video);
    expect(result.qualities.single.format, 'mp4');
    expect(
      result.qualities.single.downloadUrl,
      'https://dl.snapcdn.app/get?token=video-download',
    );
  });

  test('YouTube parses a watch-page player fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('youtube.html'), 200);

    final result = await const YouTubeExtractor(
      useNativeClient: false,
    ).extract('https://www.youtube.com/watch?v=abcdefghijk');

    expect(result.platform, VideoPlatform.youtube);
    expect(result.title, 'YouTube fixture');
    expect(result.qualities, hasLength(2));
  });

  test('Generic extractor resolves Open Graph fixture URLs', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response(
      fixture('generic.html'),
      200,
      headers: {'content-type': 'text/html'},
    );

    final result = await const GenericExtractor().extract(
      'https://fixture.example/post',
    );

    expect(result.platform, VideoPlatform.generic);
    expect(result.title, 'Generic fixture');
    expect(
      result.qualities.single.downloadUrl,
      'https://fixture.example/media/video.mp4',
    );
  });

  test('Generic extractor accepts a direct image URL', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response(
      'image bytes are not buffered by the extractor contract',
      200,
      headers: {'content-type': 'image/png'},
    );

    final result = await const GenericExtractor().extract(
      'https://fixture.example/media/photo.png',
    );

    expect(result.qualities.single.isImage, isTrue);
    expect(result.qualities.single.format, 'png');
  });

  test('Generic extractor accepts an Open Graph image-only page', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response(
      fixture('generic_image.html'),
      200,
      headers: {'content-type': 'text/html'},
    );

    final result = await const GenericExtractor().extract(
      'https://fixture.example/image-post',
    );

    expect(result.qualities.single.isImage, isTrue);
    expect(result.qualities.single.format, 'webp');
    expect(
      result.qualities.single.downloadUrl,
      'https://fixture.example/media/post-image.webp',
    );
  });
}
