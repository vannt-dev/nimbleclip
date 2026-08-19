import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/video_platform.dart';
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
  tearDown(ExtractorHttp.resetOverrides);

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
}
