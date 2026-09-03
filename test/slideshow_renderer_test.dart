import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer_android.dart';
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

  test('the channel renderer claims support only on Android', () {
    // Guards the seam: dart.library.io covers iOS and desktop as well, so the
    // conditional import cannot exclude them — only this runtime check can.
    expect(
      const MethodChannelSlideshowRenderer().isSupported,
      Platform.isAndroid,
    );
  });

  test('the channel renderer refuses to render off Android', () async {
    // The suite runs on the desktop VM, where the channel has no handler. The
    // gate has to turn the call away before it reaches one.
    if (Platform.isAndroid) return;
    await expectLater(
      const MethodChannelSlideshowRenderer().render(
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
