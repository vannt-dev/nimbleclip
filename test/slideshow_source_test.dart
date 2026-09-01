import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';

void main() {
  const source = SlideshowSource(
    imageUrls: ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
    audioUrl: 'https://cdn/song.mp3',
  );

  test('a slideshow option needs rendering and carries no download url', () {
    const option = VideoQualityOption.slideshow(
      id: 'tt_slideshow_1',
      label: SlideshowVideo(2),
      source: source,
    );
    expect(option.needsRendering, isTrue);
    expect(option.downloadUrl, isEmpty);
    // It produces a video, so it stays in the video tab's kind.
    expect(option.kind, MediaKind.video);
  });

  test('an ordinary option does not need rendering', () {
    const option = VideoQualityOption.video(
      id: 'v',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn/v.mp4',
    );
    expect(option.needsRendering, isFalse);
  });

  test('the default timing is three seconds an image at 1080x1920', () {
    expect(source.perImage, const Duration(seconds: 3));
    expect(source.width, 1080);
    expect(source.height, 1920);
  });

  test('an option with neither a url nor a source is rejected', () {
    expect(
      () => VideoQualityOption(
        id: 'x',
        label: const OriginalMp4(),
        quality: '720p',
        format: 'mp4',
        downloadUrl: '',
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('a stored option with no url still deserializes', () {
    expect(
      () => VideoQualityOption.fromJson(const {
        'id': 'legacy',
        'label': 'originalMp4',
        'quality': '720p',
        'format': 'mp4',
        'downloadUrl': '',
      }),
      returnsNormally,
    );
  });
}
