import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/views/home/widgets/platform_badges.dart';

/// With a name beside each icon the badges wrapped onto several rows and took
/// a third of the home screen, so they are icons only, on one row.
void main() {
  const shown = [
    VideoPlatform.youtube,
    VideoPlatform.tiktok,
    VideoPlatform.facebook,
    VideoPlatform.twitter,
    VideoPlatform.instagram,
    VideoPlatform.threads,
    VideoPlatform.pinterest,
    VideoPlatform.soundcloud,
    VideoPlatform.flickr,
  ];

  // the home screen's own side padding
  Widget host({void Function(VideoPlatform)? onTap}) => MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.topCenter,
          child: PlatformBadges(onPlatformTap: onTap),
        ),
      ),
    ),
  );

  Future<void> useScreen(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows an icon per platform and no names', (tester) async {
    await useScreen(tester, const Size(360, 800));
    await tester.pumpWidget(host());

    expect(find.byType(Icon), findsNWidgets(shown.length));
    expect(find.byType(Text), findsNothing);
    for (final platform in shown) {
      // the name is still there for a long press and for a screen reader
      expect(find.byTooltip(platform.displayName), findsOneWidget);
      expect(find.bySemanticsLabel(platform.displayName), findsOneWidget);
    }
  });

  for (final width in [360.0, 412.0, 800.0]) {
    testWidgets('keeps to one row on a screen $width wide', (tester) async {
      await useScreen(tester, Size(width, 800));
      await tester.pumpWidget(host());

      final tops = {
        for (final platform in shown)
          tester.getTopLeft(find.byTooltip(platform.displayName)).dy,
      };
      expect(tops, hasLength(1));
      expect(tester.getSize(find.byType(PlatformBadges)).height, lessThan(41));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('wraps instead of overflowing on a screen 320 wide', (
    tester,
  ) async {
    await useScreen(tester, const Size(320, 800));
    await tester.pumpWidget(host());

    expect(tester.takeException(), isNull);
    final badges = tester.getRect(find.byType(PlatformBadges));
    for (final platform in shown) {
      final badge = tester.getRect(find.byTooltip(platform.displayName));
      expect(badges.expandToInclude(badge), badges);
    }
    expect(badges.height, lessThan(70));
  });

  testWidgets('a tap says which platform it was', (tester) async {
    await useScreen(tester, const Size(360, 800));
    final tapped = <VideoPlatform>[];
    await tester.pumpWidget(host(onTap: tapped.add));

    await tester.tap(find.byTooltip('TikTok'));
    await tester.tap(find.byTooltip('Twitter / X'));

    expect(tapped, [VideoPlatform.tiktok, VideoPlatform.twitter]);
  });
}
