import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/core/utils/external_service_policy.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/services/extractors/facebook_extractor.dart';
import 'package:nimble_clip/services/extractors/generic_extractor.dart';
import 'package:nimble_clip/services/extractors/instagram_extractor.dart';
import 'package:nimble_clip/services/extractors/tiktok_extractor.dart';
import 'package:nimble_clip/services/extractors/twitter_extractor.dart';
import 'package:nimble_clip/services/extractors/youtube_extractor.dart';

String fixture(String name) =>
    File('test/fixtures/extractors/$name').readAsStringSync();

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  tearDown(() {
    ExtractorHttp.resetOverrides();
    ExternalServicePolicy.allowExternalServices = true;
  });

  test('external-only extractors respect the privacy policy', () async {
    ExternalServicePolicy.allowExternalServices = false;
    await expectLater(
      const TikTokExtractor().extract(
        'https://www.tiktok.com/@u/video/1',
        l10n,
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('disabled'),
        ),
      ),
    );
  });

  test('TikTok parses the API fixture', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/video/1',
      l10n,
    );

    expect(result.platform, VideoPlatform.tiktok);
    expect(result.title, 'TikTok fixture');
    expect(result.qualities, hasLength(2));
    expect(result.qualities.first.downloadUrl, endsWith('/video/hd.mp4'));
  });

  test('TikTok exposes every slideshow image as a download option', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
      l10n,
    );

    final images = result.qualities.where((option) => option.isImage).toList();
    expect(images, hasLength(2));
    expect(images.first.format, 'jpg');
    expect(images.last.downloadUrl, endsWith('/images/image-2.webp'));
    expect(images.last.format, 'webp');
  });

  test('X parses and sorts the FxTwitter fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('twitter.json'), 200);

    final result = await const TwitterExtractor().extract(
      'https://x.com/fixture/status/123456789',
      l10n,
    );

    expect(result.platform, VideoPlatform.twitter);
    expect(result.author, 'Fixture User');
    expect(result.qualities.first.quality, '720p');
    expect(result.qualities, hasLength(2));
  });

  test('X exposes videos and photos from the same post', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('twitter_mixed.json'), 200);

    final result = await const TwitterExtractor().extract(
      'https://x.com/fixture/status/987654321',
      l10n,
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(result.qualities.where((option) => !option.isImage), hasLength(1));
  });

  test('Facebook parses playable URLs from a page fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/watch/?v=123456',
      l10n,
    );

    expect(result.platform, VideoPlatform.facebook);
    expect(result.id, '123456');
    expect(result.title, 'Facebook Fixture');
    expect(result.qualities, hasLength(2));
  });

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
        l10n,
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
      l10n,
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
      l10n,
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
        l10n,
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
        l10n,
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

  test('Facebook keeps video and photos from a mixed public post', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('facebook_mixed.html'), 200);

    final result = await const FacebookExtractor().extract(
      'https://www.facebook.com/example/posts/mixed123',
      l10n,
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(
      result.qualities.where(
        (option) => !option.isImage && !option.isAudioOnly,
      ),
      hasLength(1),
    );
  });

  test('Instagram parses a public embed fixture', () async {
    ExtractorHttp.getOverride = (_, _) async =>
        http.Response(fixture('instagram.html'), 200);

    final result = await const InstagramExtractor().extract(
      'https://www.instagram.com/reel/fixture123/',
      l10n,
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
      l10n,
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
      l10n,
    );

    expect(result.qualities.where((option) => option.isImage), hasLength(2));
    expect(
      result.qualities.where(
        (option) => !option.isImage && !option.isAudioOnly,
      ),
      hasLength(1),
    );
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
        l10n,
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
      l10n,
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
    ).extract('https://www.youtube.com/watch?v=abcdefghijk', l10n);

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
      l10n,
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
      l10n,
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
      l10n,
    );

    expect(result.qualities.single.isImage, isTrue);
    expect(result.qualities.single.format, 'webp');
    expect(
      result.qualities.single.downloadUrl,
      'https://fixture.example/media/post-image.webp',
    );
  });
}
