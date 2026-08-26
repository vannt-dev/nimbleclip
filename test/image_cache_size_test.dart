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
}
