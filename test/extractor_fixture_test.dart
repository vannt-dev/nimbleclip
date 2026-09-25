import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:nimble_clip/services/extractors/instagram_fallback_client.dart';
import 'package:nimble_clip/services/extractors/tiktok_extractor.dart';
import 'package:nimble_clip/services/extractors/twitter_extractor.dart';
import 'package:nimble_clip/services/extractors/youtube_extractor.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

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

  test('TikTok offers one rendered slideshow for a photo post', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
    );

    final rendered = result.qualities.where((o) => o.needsRendering).toList();
    expect(rendered, hasLength(1));
    expect(rendered.single.format, 'mp4');
    expect(rendered.single.slideshow!.imageUrls, hasLength(2));
    // Relative CDN paths must already be absolute by the time they are handed
    // to the renderer, which has no idea what TikWM's host is.
    expect(rendered.single.slideshow!.imageUrls.last, startsWith('http'));
    expect(rendered.single.slideshow!.audioUrl, isNotNull);
    expect((rendered.single.label as SlideshowVideo).imageCount, 2);
  });

  test('TikTok offers no slideshow for a video post', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/video/1',
    );

    expect(result.qualities.where((o) => o.needsRendering), isEmpty);
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

  // Offline, both services fail on the network, yet the only thing the user
  // was ever told is that the post has no video. The causes must survive into
  // the diagnostics, as the YouTube native error now does.
  test('X keeps each service failure in the diagnostics', () async {
    ExtractorHttp.getOverride = (uri, _) async {
      if (uri.host == 'api.fxtwitter.com') {
        throw const SocketException('Failed host lookup');
      }
      return http.Response('busy', 503);
    };

    await expectLater(
      const TwitterExtractor().extract('https://x.com/fixture/status/1'),
      throwsA(
        isA<ExtractionException>()
            .having(
              (e) => e.failure.kind,
              'kind',
              ExtractionFailureKind.xNoVideo,
            )
            .having(
              (e) => e.suppressedError,
              'suppressedError',
              allOf(
                contains('FxTwitter'),
                contains('Failed host lookup'),
                contains('VxTwitter'),
                contains('HTTP 503'),
              ),
            ),
      ),
    );
  });

  test('Instagram keeps each strategy failure in the diagnostics', () async {
    ExtractorHttp.getOverride = (uri, _) async => uri.path.contains('/embed/')
        ? http.Response('gone', 404)
        : throw const SocketException('Connection reset');

    await expectLater(
      InstagramExtractor(
        externalServiceAccess: const FixedExternalServiceAccess(true),
        fallbackClient: _FailingInstagramFallback(),
      ).extract('https://www.instagram.com/p/abc123/'),
      throwsA(
        isA<ExtractionException>()
            .having(
              (e) => e.failure.kind,
              'kind',
              ExtractionFailureKind.instagramLoginRequired,
            )
            .having(
              (e) => e.suppressedError,
              'suppressedError',
              allOf(
                contains('embed page: HTTP 404'),
                contains('post page'),
                contains('Connection reset'),
                contains('SnapInsta'),
                contains('service down'),
              ),
            ),
      ),
    );
  });

  test('Facebook keeps each page failure in the diagnostics', () async {
    ExtractorHttp.getOverride = (uri, _) async => uri.host == 'm.facebook.com'
        ? http.Response('blocked', 403)
        : throw const SocketException('Network is unreachable');

    await expectLater(
      const FacebookExtractor(
        externalServiceAccess: FixedExternalServiceAccess(false),
      ).extract('https://www.facebook.com/watch/?v=123'),
      throwsA(
        isA<ExtractionException>().having(
          (e) => e.suppressedError,
          'suppressedError',
          allOf(
            contains('page: '),
            contains('Network is unreachable'),
            contains('embed: '),
            contains('mobile: HTTP 403'),
          ),
        ),
      ),
    );
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

  // A reel can be public and still serve an anonymous visitor nothing, because
  // Facebook gates it as 18+. Reporting that as "make sure the post is public"
  // sends the user to check the one thing that is already fine. The route name
  // is the only signal in the document — the sentence a reader sees is drawn
  // by script and never appears in the HTML.
  test('Facebook tells an age-gated reel apart from a private one', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response(
      '<html><body><script>'
      '{"__crn":"comet.fbweb.CometAgeInappropriateLoggedOutErrorRoute"}'
      '</script></body></html>',
      200,
    );

    await expectLater(
      const FacebookExtractor().extract(
        'https://www.facebook.com/reel/1831368848220203/',
      ),
      throwsA(
        isA<ExtractionException>().having(
          (error) => error.failure.kind,
          'failure kind',
          ExtractionFailureKind.facebookAgeRestricted,
        ),
      ),
    );
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

  // Toolspy moved its API to the www host and answers the bare domain with a
  // 308. `http` does not follow a redirect for a POST, so the gallery check
  // failed on every post and each album shrank to its cover photo.
  test('Facebook asks the gallery service at the host that answers', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_image.html'), 200);
    ExtractorHttp.postOverride = (uri, _, _) async =>
        uri.host == 'www.toolspy.net'
        ? http.Response(fixture('facebook_fallback.json'), 200)
        : http.Response(
            '{"redirect": "https://www.toolspy.net${uri.path}"}',
            308,
          );

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/example/posts/654321',
    );

    expect(result.galleryNotice, isNull);
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

  // Every shape a person copies must come out as an ID the library accepts:
  // the library parses URLs itself and rejects some of these outright.
  test('YouTube reduces every copied link shape to a library-valid ID', () {
    const cases = {
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://www.youtube.com/watch?feature=share&v=dQw4w9WgXcQ':
          'dQw4w9WgXcQ',
      'https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s': 'dQw4w9WgXcQ',
      'https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=abc': 'dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
      'https://youtu.be/dQw4w9WgXcQ?si=odC7xSUW-rNQw5PZ&t=10': 'dQw4w9WgXcQ',
      'https://youtube.com/shorts/uX_MyFPrkxA?si=odC7xSUW-rNQw5PZ':
          'uX_MyFPrkxA',
      'https://m.youtube.com/shorts/uX_MyFPrkxA?feature=share': 'uX_MyFPrkxA',
      'https://www.youtube.com/shorts/uX_MyFPrkxA/': 'uX_MyFPrkxA',
      'https://www.youtube.com/live/dQw4w9WgXcQ?si=abc': 'dQw4w9WgXcQ',
      'https://www.youtube.com/embed/dQw4w9WgXcQ?start=5': 'dQw4w9WgXcQ',
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ': 'dQw4w9WgXcQ',
    };

    cases.forEach((url, id) {
      final parsed = YouTubeExtractor.videoIdFrom(url);
      expect(parsed, id, reason: url);
      expect(yt_lib.VideoId(parsed!).value, id, reason: url);
    });
    expect(YouTubeExtractor.videoIdFrom('https://www.youtube.com/'), isNull);
  });

  // Regression: a Shorts share link carries `?si=`, which the library's own
  // Shorts pattern rejects before sending a single request. The native client
  // must be handed the parsed ID, not the URL.
  test(
    'YouTube native client receives a Shorts share link as its ID',
    () async {
      final requested = <Uri>[];
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response(fixture('youtube.html'), 200);

      await YouTubeExtractor(
        nativeHttpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 404);
        }),
      ).extract('https://youtube.com/shorts/uX_MyFPrkxA?si=odC7xSUW-rNQw5PZ');

      expect(
        requested.map((uri) => uri.toString()),
        contains(contains('uX_MyFPrkxA')),
      );
    },
  );

  // The watch-page fallback reports the last failure, which hid the native
  // client's own error: the Shorts bug above surfaced as "no streams".
  test(
    'YouTube keeps the native client error when the fallback fails',
    () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response('<html>no player here</html>', 200);

      final failure = expectLater(
        YouTubeExtractor(
          nativeHttpClient: MockClient(
            (_) async => throw http.ClientException('native offline'),
          ),
        ).extract('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        throwsA(
          isA<ExtractionException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ExtractionFailureKind.youtubeNoPlayerData,
              )
              .having(
                (e) => e.suppressedError,
                'suppressedError',
                allOf(contains('native-client'), contains('native offline')),
              ),
        ),
      );
      await failure;
    },
  );

  // youtube_explode already retries a watch page five times before giving up,
  // so a transient failure reaching us means YouTube is refusing for now. The
  // fallback's "no streams" would tell the user the video is at fault.
  test(
    'YouTube reports a temporary refusal rather than missing streams',
    () async {
      ExtractorHttp.getOverride = (_, _) async =>
          http.Response('<html>no player here</html>', 200);
      var watchPageRequests = 0;

      await expectLater(
        YouTubeExtractor(
          nativeHttpClient: MockClient((request) async {
            if (request.url.path == '/watch') watchPageRequests++;
            // A page with cookies but no initial data: the shape YouTube
            // serves while it is throttling a client.
            return http.Response(
              '<html></html>',
              200,
              headers: {'set-cookie': 'VISITOR_INFO1_LIVE=x; path=/'},
              // The library validates against the originating request, which
              // MockClient leaves unset unless it is passed through.
              request: request,
            );
          }),
        ).extract('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        throwsA(
          isA<ExtractionException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ExtractionFailureKind.youtubeTemporarilyUnavailable,
              )
              .having(
                (e) => e.suppressedError,
                'suppressedError',
                contains('TransientFailureException'),
              ),
        ),
      );
      expect(watchPageRequests, greaterThan(1));
    },
  );

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

class _FailingInstagramFallback implements InstagramFallbackClient {
  @override
  Future<String?> search(String postUrl) async =>
      throw Exception('service down');
}
