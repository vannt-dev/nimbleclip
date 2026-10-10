import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/extractors/youtube_extractor.dart';

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
    // The shape the YouTube app shares, `?si=` and all. The library's own
    // Shorts pattern once rejected every such link while the plain watch URL
    // above kept passing.
    'YouTube Short from a share link': (
      url: 'https://youtube.com/shorts/uX_MyFPrkxA?si=odC7xSUW-rNQw5PZ',
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
    // Threads hands a post's media only to a search crawler, so these two are
    // the first to notice if it stops doing that.
    'Threads video': (
      url: 'https://www.threads.com/@nasa/post/Dcqa7s8gu-P',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    // The old domain and the tracking parameter the Share action appends.
    'Threads carousel from a share link': (
      url: 'https://www.threads.net/@nasa/post/DdhbVBwlRP_?xmt=share',
      minimumMedia: 2,
      minimumVideos: 0,
    ),
    // Seven pictures and two videos in one post.
    'Threads carousel mixing pictures and videos': (
      url: 'https://www.threads.com/@zuck/post/Ddt7cL5EfUG',
      minimumMedia: 9,
      minimumVideos: 2,
    ),
    // Words of its own, and the video of the post it quotes.
    'Threads post quoting a video': (
      url: 'https://www.threads.com/@natgeo/post/Dd_i0KnDfUr',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    // A video carried over from Instagram rather than attached to the post.
    'Threads post with an inline video': (
      url: 'https://www.threads.com/@nasa/post/DdEwHNClPdc',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    'Threads short link': (
      url: 'https://www.threads.com/t/Dcqa7s8gu-P',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    'Pinterest video pin': (
      url: 'https://www.pinterest.com/pin/703335666829201694/',
      minimumMedia: 1,
      minimumVideos: 1,
    ),
    'Pinterest picture pin': (
      url: 'https://www.pinterest.com/pin/99360735500167749/',
      minimumMedia: 1,
      minimumVideos: 0,
    ),
    'SoundCloud track': (
      url: 'https://soundcloud.com/forss/flickermood',
      minimumMedia: 1,
      minimumVideos: 0,
    ),
    'Flickr photo': (
      url: 'https://www.flickr.com/photos/signalcorpsarchive/54313219625/',
      minimumMedia: 1,
      minimumVideos: 0,
    ),
    'Flickr video': (
      url: 'https://www.flickr.com/photos/sergeysmirnov/55470861998/',
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
        // A slideshow or a merged video is produced on the device and so has
        // no download URL of its own; the sources it is built from must
        // resolve instead.
        bool resolves(String url) => Uri.tryParse(url)?.hasScheme == true;
        for (final option in metadata.qualities) {
          final slideshow = option.slideshow;
          final merge = option.merge;
          final urls = slideshow != null
              ? [...slideshow.imageUrls, ?slideshow.audioUrl]
              : merge != null
              ? [merge.videoUrl, merge.audioUrl]
              : [option.downloadUrl];
          expect(urls, isNotEmpty, reason: option.id);
          expect(urls.every(resolves), isTrue, reason: option.id);
        }
      },
      skip: !_runLive
          ? 'Run tool/check_live_extractors.ps1 to test live services.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  // An address that resolves is not yet a file that arrives: a download can
  // stop part-way while every case above stays green. So this asks for the
  // last bytes of each stream of a ten-minute video, as a download's last
  // part does.
  test(
    'YouTube serves the end of every stream of a long video',
    () async {
      final metadata = await const YouTubeExtractor(
        canMergeStreams: true,
      ).extract('https://www.youtube.com/watch?v=aqz-KE-bpKQ');
      final merged = metadata.qualities.where((option) => option.merge != null);
      expect(merged, isNotEmpty, reason: 'no quality above 360p was offered');

      final client = http.Client();
      addTearDown(client.close);
      Future<int> lastBytes(String url, int total) async {
        final request = http.Request('GET', Uri.parse(url))
          ..headers['Range'] = 'bytes=${total - 65536}-${total - 1}';
        final response = await client.send(request);
        await response.stream.drain<void>();
        return response.statusCode;
      }

      for (final option in metadata.qualities) {
        final merge = option.merge;
        final sources = merge != null
            ? [
                (merge.videoUrl, merge.videoBytes ?? 0),
                (merge.audioUrl, merge.audioBytes ?? 0),
              ]
            : [(option.downloadUrl, option.sizeBytes ?? 0)];
        for (final (url, total) in sources) {
          expect(total, greaterThan(65536), reason: option.id);
          expect(await lastBytes(url, total), 206, reason: option.id);
        }
      }
    },
    skip: !_runLive
        ? 'Run tool/check_live_extractors.ps1 to test live services.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

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

  // A photo whose owner switched downloading off must be refused, not saved
  // at the size the page happens to show.
  test(
    'Flickr photo with downloads off is refused',
    () async {
      await expectLater(
        registry.extract('https://www.flickr.com/photos/bees/2341623661/'),
        throwsA(
          isA<ExtractionException>().having(
            (error) => error.failure.kind,
            'failure kind',
            ExtractionFailureKind.flickrDownloadDisabled,
          ),
        ),
      );
    },
    skip: !_runLive
        ? 'Run tool/check_live_extractors.ps1 to test live services.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
