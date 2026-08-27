import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/image_cache_size.dart';

void main() {
  testWidgets('image cache width follows the device pixel ratio', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.625),
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(imageCacheWidth(context, 64), 168);
    expect(imageCacheWidth(context, 0), 1);
  });

  testWidgets('the image cache budget is smaller than Flutter default', (
    tester,
  ) async {
    final cache = PaintingBinding.instance.imageCache;
    final defaultSizeBytes = cache.maximumSizeBytes;

    addTearDown(() {
      cache.maximumSizeBytes = defaultSizeBytes;
      cache.maximumSize = 1000;
    });

    configureImageCacheBudget();

    // Flutter defaults to 100 MB of decoded images, which is a large share of
    // the heap on a low-RAM device showing a grid of full-size post photos.
    expect(cache.maximumSizeBytes, lessThan(defaultSizeBytes));
    expect(cache.maximumSizeBytes, 48 << 20);
    expect(cache.maximumSize, 200);
  });

  testWidgets('preview cache width allows zooming without a full decode', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 3, size: Size(400, 800)),
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    // 400 logical px * 3 dpr * 2 headroom for InteractiveViewer's zoom.
    expect(previewCacheWidth(context), 2400);
  });

  testWidgets('preview cache width is capped on very large screens', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 4, size: Size(1600, 2560)),
        child: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox();
          },
        ),
      ),
    );

    // Without a ceiling this would ask for a 12800px decode.
    expect(previewCacheWidth(context), 4096);
  });
}
