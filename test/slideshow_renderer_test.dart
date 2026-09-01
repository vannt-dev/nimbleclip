import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer_stub.dart';

void main() {
  test('the stub renderer reports itself unsupported', () {
    expect(const UnsupportedSlideshowRenderer().isSupported, isFalse);
  });

  test('the stub renderer refuses to render', () async {
    await expectLater(
      const UnsupportedSlideshowRenderer().render(
        imagePaths: const ['/tmp/1.jpg'],
        perImage: const Duration(seconds: 3),
        width: 1080,
        height: 1920,
        outputPath: '/tmp/out.mp4',
      ),
      throwsA(
        isA<SlideshowException>().having(
          (e) => e.kind,
          'kind',
          SlideshowFailureKind.encoderUnavailable,
        ),
      ),
    );
  });
}
