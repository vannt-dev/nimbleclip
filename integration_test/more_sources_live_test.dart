import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/extractors/streams/hls_fetcher.dart';
import 'package:nimble_clip/services/extractors/streams/stream_fetcher.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:path_provider/path_provider.dart';

const _runLive = bool.fromEnvironment('RUN_LIVE_EXTRACTOR_TESTS');

/// On-device checks of Pinterest, SoundCloud and Flickr against the real
/// services: the link is analysed, the media is fetched the way a download
/// fetches it, and the file is read back.
///
///   flutter test integration_test/more_sources_live_test.dart -d emulator-5554 --dart-define=RUN_LIVE_EXTRACTOR_TESTS=true
///
/// Skipped without the define, so a build that only runs the device tests
/// does not depend on three websites.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const slideshow = MethodChannel('com.vannt.nimbleclip/slideshow');
  final registry = ExtractorRegistry();
  const skip = _runLive
      ? false
      : 'Pass --dart-define=RUN_LIVE_EXTRACTOR_TESTS=true to test live services.';
  const timeout = Timeout(Duration(minutes: 4));

  Future<Map<String, dynamic>> probe(String path) async => (await slideshow
      .invokeMapMethod<String, dynamic>('probe', {'path': path}))!;

  Future<Directory> workspace(String name) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/$name');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    return dir..createSync(recursive: true);
  }

  test(
    'Pinterest: a size only the stream has is joined into a playable video',
    () async {
      final pin = await registry.extract(
        'https://www.pinterest.com/pin/703335666829201694/',
      );
      expect(pin.platform, VideoPlatform.pinterest);
      // The file the page names, as on every platform.
      final file = pin.qualities.firstWhere((option) => option.stream == null);
      expect(file.downloadUrl, endsWith('.mp4'));
      // And, on a device that can join them, the stream's other sizes.
      final joined = pin.qualities.where((option) => option.stream != null);
      expect(joined, isNotEmpty);
      final source = joined.last.stream! as HlsSource;

      final dir = await workspace('pinterest_live');
      final video = File('${dir.path}/video.stream');
      final audio = File('${dir.path}/audio.stream');
      await fetchHlsToFile(source.videoPlaylistUrl, video);
      expect(source.audioPlaylistUrl, isNotNull);
      await fetchHlsToFile(source.audioPlaylistUrl!, audio);

      final out = await createSlideshowRenderer().mux(
        videoPath: video.path,
        audioPath: audio.path,
        outputPath: '${dir.path}/pin.mp4',
        audioOptional: true,
      );
      final info = await probe(out);
      expect(info['hasVideo'], isTrue);
      expect(info['hasAudio'], isTrue);
      // The page says how long the video is; the joined file must agree.
      final expected = pin.duration!.inMilliseconds;
      expect(
        info['durationMs'] as int,
        inInclusiveRange(expected - 2000, expected + 2000),
      );
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'SoundCloud: the file is the whole track as an MP3',
    () async {
      final track = await registry.extract(
        'https://soundcloud.com/forss/flickermood',
      );
      final option = track.qualities.single;
      expect(option.isAudioOnly, isTrue);

      final dir = await workspace('soundcloud_live');
      final file = File('${dir.path}/track.mp3');
      await fetchStreamToFile(option.downloadUrl, file);

      // An ID3 tag or an MPEG audio frame, not an error page.
      final head = file.openSync().readSync(3);
      final isMp3 =
          String.fromCharCodes(head) == 'ID3' ||
          (head[0] == 0xFF && head[1] & 0xE0 == 0xE0);
      expect(isMp3, isTrue);
      final info = await probe(file.path);
      expect(info['hasAudio'], isTrue);
      // Not the 30-second preview: what SoundCloud says the track lasts.
      final expected = track.duration!.inMilliseconds;
      expect(
        info['durationMs'] as int,
        inInclusiveRange(expected - 3000, expected + 3000),
      );
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'Flickr: a video address leads to a playable file, a photo to a picture',
    () async {
      final video = await registry.extract(
        'https://www.flickr.com/photos/sergeysmirnov/55470861998/',
      );
      // The smallest, to keep the check quick. Its address is on flickr.com
      // and redirects to the file.
      final option = video.qualities.last;
      expect(Uri.parse(option.downloadUrl).host, 'www.flickr.com');
      final dir = await workspace('flickr_live');
      final file = File('${dir.path}/video.mp4');
      await fetchStreamToFile(option.downloadUrl, file);
      final info = await probe(file.path);
      expect(info['hasVideo'], isTrue);
      expect(info['durationMs'] as int, greaterThan(1000));

      final photo = await registry.extract('https://flic.kr/p/2qKtrX8');
      final picture = photo.qualities.single;
      expect(picture.isImage, isTrue);
      final http.Response response = await ExtractorHttp.get(
        picture.downloadUrl,
        timeout: const Duration(seconds: 60),
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], startsWith('image/'));
      // The original, which is megabytes, not a thumbnail.
      expect(response.bodyBytes.length, greaterThan(500 * 1024));
    },
    skip: skip,
    timeout: timeout,
  );
}
