import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/views/home/widgets/media_preview_dialog.dart';
import 'package:nimble_clip/views/player/video_player_screen.dart';

/// Looking at one photo of an album meant closing it and tapping the next, so
/// the preview carries the whole set and is swiped through.
void main() {
  List<VideoQualityOption> photos(int count) => [
    for (var index = 0; index < count; index++)
      VideoQualityOption.image(
        id: 'image-$index',
        mediaId: 'image-$index',
        label: ImageIndex(index + 1),
        format: 'jpg',
        downloadUrl: 'https://cdn.example.com/photo-$index.jpg',
      ),
  ];

  Widget host(List<VideoQualityOption> options, int initialIndex) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaPreviewDialog(options: options, initialIndex: initialIndex),
      );

  Set<String> shownUrls(WidgetTester tester) => tester
      .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
      .map((image) => image.imageUrl)
      .toSet();

  testWidgets('opens on the photo that was tapped, not the first', (
    tester,
  ) async {
    await tester.pumpWidget(host(photos(5), 2));
    await tester.pump();

    expect(shownUrls(tester), contains('https://cdn.example.com/photo-2.jpg'));
    expect(find.text('3 / 5'), findsOneWidget);
  });

  testWidgets('swiping moves to the next photo', (tester) async {
    await tester.pumpWidget(host(photos(5), 0));
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    // Not pumpAndSettle: the placeholder spinner never stops, so the tree
    // never settles. One pump past the page animation is what is needed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(shownUrls(tester), contains('https://cdn.example.com/photo-1.jpg'));
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('swiping back from the first photo stays put', (tester) async {
    await tester.pumpWidget(host(photos(3), 0));
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(500, 0));
    // Not pumpAndSettle: the placeholder spinner never stops, so the tree
    // never settles. One pump past the page animation is what is needed.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1 / 3'), findsOneWidget);
  });

  group('video playlist', _videoSwipeTests);

  testWidgets('a lone photo shows no position counter', (tester) async {
    await tester.pumpWidget(host(photos(1), 0));
    await tester.pump();

    // Nothing to move between, so the counter would be noise.
    expect(find.text('1 / 1'), findsNothing);
  });
}

/// The video player carries the post's other videos the same way, so a
/// highlight can be looked through without backing out to the grid each time.
void _videoSwipeTests() {
  List<VideoQualityOption> videos(int count) => [
    for (var index = 0; index < count; index++)
      VideoQualityOption.video(
        id: 'video-$index',
        mediaId: 'video-$index',
        label: VideoIndex(index + 1),
        quality: 'Original',
        format: 'mp4',
        downloadUrl: 'https://cdn.example.com/clip-$index.mp4',
      ),
  ];

  Widget host(List<VideoQualityOption>? playlist, int initialIndex) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: VideoPlayerScreen(
          title: 'Clip',
          videoUrl: playlist?[initialIndex].downloadUrl,
          playlist: playlist,
          initialIndex: initialIndex,
        ),
      );

  testWidgets('opens on the video that was tapped', (tester) async {
    await tester.pumpWidget(host(videos(3), 1));
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('swiping moves to the next video', (tester) async {
    await tester.pumpWidget(host(videos(3), 0));
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('a single video is not made swipeable', (tester) async {
    await tester.pumpWidget(host(videos(1), 0));
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('1 / 1'), findsNothing);
  });
}
