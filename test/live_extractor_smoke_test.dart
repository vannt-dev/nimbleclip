import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/services/extractors/registry.dart';

const _runLive = bool.fromEnvironment('RUN_LIVE_EXTRACTOR_TESTS');
const _instagramImageUrl = String.fromEnvironment('INSTAGRAM_IMAGE_URL');
const _instagramVideoUrl = String.fromEnvironment('INSTAGRAM_VIDEO_URL');

void main() {
  final registry = ExtractorRegistry();

  // [minimumVideos] is what keeps a case honest about its own name. Counting
  // media alone let a case called "video" pass on photographs: when Facebook
  // began refusing the page request, the gallery cases below still went green,
  // because the mobile strategy yielded one image, which sent the gallery to
  // the fallback service, which returned the whole set. Facebook's own page
  // fetch was dead throughout and nothing noticed.
  final cases = <String, ({String url, int minimumMedia, int minimumVideos})>{
    if (_instagramImageUrl.isNotEmpty)
      'Instagram carousel': (
        url: _instagramImageUrl,
        minimumMedia: 2,
        minimumVideos: 0,
      ),
    if (_instagramVideoUrl.isNotEmpty)
      'Instagram video': (
        url: _instagramVideoUrl,
        minimumMedia: 1,
        minimumVideos: 1,
      ),
    'YouTube video': (
      url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    'Facebook gallery': (
      url: 'https://www.facebook.com/cebuanafinance/posts/662287040177856/',
      minimumMedia: 2,
      minimumVideos: 0,
    ),
    // A share link is the shape a person actually copies, and it reaches the
    // gallery by a different route than the permalink above: it never
    // redirects, so the fallback has to accept the `/share/` URL as it stands.
    // The permalink case passed throughout the window where this one returned
    // a single photo, which is why it is listed separately.
    'Facebook gallery from a share link': (
      url: 'https://www.facebook.com/share/1CYGwgPahk/',
      minimumMedia: 2,
      minimumVideos: 0,
    ),
    'X gallery': (
      url: 'https://x.com/SpaceX/status/2000459900460347480',
      minimumMedia: 2,
      minimumVideos: 0,
    ),
    'X video': (
      url: 'https://x.com/SpaceX/status/1897790210219311202',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    'TikTok slideshow': (
      url: 'https://www.tiktok.com/@qq.mm.pp/photo/7479037796326362385',
      minimumMedia: 2,
      minimumVideos: 0,
    ),
    'TikTok video': (
      url: 'https://www.tiktok.com/@sydneygurung/video/7663135895184362770',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
  };

  for (final entry in cases.entries) {
    test(
      entry.key,
      () async {
        final metadata = await registry.extract(entry.value.url);
        expect(
          metadata.qualities.length,
          greaterThanOrEqualTo(entry.value.minimumMedia),
        );
        expect(
          metadata.qualities
              .where((option) => !option.isImage && !option.isAudioOnly)
              .length,
          greaterThanOrEqualTo(entry.value.minimumVideos),
          reason: 'a case named for video must not pass on photographs alone',
        );
        expect(
          metadata.qualities.every(
            (option) => Uri.tryParse(option.downloadUrl)?.hasScheme == true,
          ),
          isTrue,
        );
      },
      skip: !_runLive
          ? 'Run tool/check_live_extractors.ps1 to test live services.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  // The outage that prompted this check never reached parsing: Facebook
  // answered 400 to a page GET that claimed a browser User-Agent without the
  // Sec-Fetch headers a navigation carries, so every reel and share link died
  // at the transport. The cases above could not see it — they are galleries,
  // and a gallery survives on the fallback service alone.
  //
  // These paths name nothing that exists, which is the point: no post can be
  // deleted out from under the check, so it never rots into a false alarm. A
  // 404 is a fine answer. A 400 means Facebook rejected the shape of the
  // request, which is the regression.
  test(
    'Facebook accepts the request shape page fetches use',
    () async {
      for (final path in const [
        '/reel/1/',
        '/share/r/zzzzzzzzzz/',
        '/share/p/zzzzzzzzzz/',
      ]) {
        final response = await ExtractorHttp.get(
          'https://www.facebook.com$path',
        );
        expect(response.statusCode, isNot(400), reason: path);
      }
    },
    skip: !_runLive
        ? 'Run tool/check_live_extractors.ps1 to test live services.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
