import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/external_service_policy.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/facebook_extractor.dart';
import 'package:nimble_clip/services/extractors/facebook_fallback_client.dart';
import 'package:nimble_clip/services/extractors/facebook_video_fallback_client.dart';

/// A relay link as the service writes it: the file's own address is the `url`
/// claim of an unverified token.
String _relay(String fileUrl) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token = [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'url': fileUrl, 'filename': 'clip.mp4'}),
    'signature',
  ].join('.');
  return 'https://dl.relay.example/get?token=$token';
}

String _answer() =>
    '''
<div id="fb_page" class="detail">
  <div class="thumbnail"><div class="image-fb open-popup">
    <img src="https://cdn.example/thumb.jpg?a=1&amp;b=2">
  </div></div>
  <div class="content"><div class="clearfix">
    <h3>Facebook Video #4431423920505269</h3><p>0:15</p>
  </div></div>
</div>
<table><tbody>
  <tr><td class="video-quality">720p (HD)</td><td>No</td>
    <td><a href="${_relay('https://video.cdn.example/hd.mp4?x=1')}" rel="nofollow">Download</a></td></tr>
  <tr><td class="video-quality">360p (SD)</td><td>No</td>
    <td><a href="https://plain.example/sd.mp4">Download</a></td></tr>
  <tr><td class="video-quality">1080p</td><td>Yes</td>
    <td><button data-videourl="x">Render</button></td></tr>
</tbody></table>
<table><tbody>
  <tr><td class="video-quality">320kbps</td><td><a href="#">Download</a></td></tr>
</tbody></table>
''';

class _FakeVideoService implements FacebookVideoFallbackClient {
  _FakeVideoService(this.answer);

  final FacebookFallbackVideo? answer;
  final List<String> asked = [];

  @override
  Future<FacebookFallbackVideo?> find(String postUrl) async {
    asked.add(postUrl);
    return answer;
  }
}

class _NoPhotos implements FacebookFallbackClient {
  const _NoPhotos();

  @override
  Future<List<String>> extractImageUrls(String postUrl) async => const [];
}

void main() {
  group('the service answer', () {
    test('lists the files that exist, by the address behind the relay', () {
      final video = X2DownloadFacebookFallbackClient.parse(_answer())!;

      expect(video.files, [
        (quality: '720p (HD)', url: 'https://video.cdn.example/hd.mp4?x=1'),
        (quality: '360p (SD)', url: 'https://plain.example/sd.mp4'),
      ]);
      expect(video.id, '4431423920505269');
      expect(video.title, 'Facebook Video #4431423920505269');
      expect(video.thumbnailUrl, 'https://cdn.example/thumb.jpg?a=1&b=2');
      expect(video.duration, const Duration(seconds: 15));
    });

    test('with no file is no answer', () {
      expect(
        X2DownloadFacebookFallbackClient.parse('<p>Video not found</p>'),
        isNull,
      );
    });
  });

  group('a link Facebook shows no video for', () {
    const story = 'https://www.facebook.com/stories/123/abc/?view_single=1';
    const found = FacebookFallbackVideo(
      id: '99',
      title: 'Facebook Video #99',
      thumbnailUrl: 'https://cdn.example/thumb.jpg',
      duration: Duration(seconds: 15),
      files: [
        (quality: '360p (SD)', url: 'https://video.cdn.example/sd.mp4'),
        (quality: '720p (HD)', url: 'https://video.cdn.example/hd.mp4'),
      ],
    );

    setUp(() {
      // What an anonymous request for a story gets: the login page.
      ExtractorHttp.getOverride = (_, _) async => http.Response(
        '<html><head><title>Log in to Facebook</title></head>'
        '<body><form id="login_form"></form></body></html>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
      ExtractorHttp.postOverride = (_, _, _) async => http.Response('{}', 200);
    });
    tearDown(ExtractorHttp.resetOverrides);

    test('is offered from the service, best quality first', () async {
      final service = _FakeVideoService(found);

      final result = await FacebookExtractor(
        fallbackClient: const _NoPhotos(),
        videoFallbackClient: service,
      ).extract(story);

      expect(service.asked, [story]);
      expect(result.platform, VideoPlatform.facebook);
      expect(result.id, '99');
      expect(result.coverUrl, 'https://cdn.example/thumb.jpg');
      expect(result.duration, const Duration(seconds: 15));
      expect(result.qualities.map((option) => option.quality), [
        '720p',
        '360p',
      ]);
      expect(
        result.qualities.first.downloadUrl,
        'https://video.cdn.example/hd.mp4',
      );
    });

    test('keeps Facebook\'s verdict when the service has nothing', () async {
      await expectLater(
        FacebookExtractor(
          fallbackClient: const _NoPhotos(),
          videoFallbackClient: _FakeVideoService(null),
        ).extract(story),
        throwsA(
          isA<ExtractionException>().having(
            (error) => error.failure.kind,
            'failure kind',
            ExtractionFailureKind.facebookNoVideo,
          ),
        ),
      );
    });

    test('is not sent anywhere when external services are off', () async {
      final service = _FakeVideoService(found);

      await expectLater(
        FacebookExtractor(
          externalServiceAccess: const FixedExternalServiceAccess(false),
          fallbackClient: const _NoPhotos(),
          videoFallbackClient: service,
        ).extract(story),
        throwsA(isA<ExtractionException>()),
      );
      expect(service.asked, isEmpty);
    });
  });
}
