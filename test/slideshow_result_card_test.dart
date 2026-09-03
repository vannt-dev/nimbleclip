import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:nimble_clip/views/home/widgets/video_result_card.dart';

/// Reports whatever support the test needs; `render` is never reached, because
/// the card only ever asks whether it could be.
class _Renderer implements SlideshowRenderer {
  const _Renderer({required this.isSupported});

  @override
  final bool isSupported;

  @override
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
  }) async => throw UnimplementedError();
}

const _image = VideoQualityOption(
  id: 'img-1',
  label: ImageIndex(1),
  quality: 'Original',
  format: 'jpg',
  downloadUrl: 'https://cdn.example.com/1.jpg',
  kind: MediaKind.image,
);

const _slideshow = VideoQualityOption.slideshow(
  id: 'tt_slideshow_post',
  label: SlideshowVideo(2),
  source: SlideshowSource(
    imageUrls: [
      'https://cdn.example.com/1.jpg',
      'https://cdn.example.com/2.jpg',
    ],
    audioUrl: 'https://cdn.example.com/song.mp3',
  ),
);

final _metadata = VideoMetadata(
  id: 'post',
  originalUrl: 'https://www.tiktok.com/@u/photo/1',
  title: 'A photo post',
  author: 'Creator',
  coverUrl: 'https://cdn.example.com/cover.jpg',
  platform: VideoPlatform.tiktok,
  qualities: const [_slideshow, _image],
);

Widget _host({
  required bool supported,
  ValueChanged<List<VideoQualityOption>>? onDownload,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: VideoResultCard(
        metadata: _metadata,
        selectedQuality: _image,
        onQualitySelected: (_) {},
        onDownload: onDownload ?? (_) {},
        onPreview: () {},
        slideshowRenderer: _Renderer(isSupported: supported),
      ),
    ),
  ),
);

void main() {
  testWidgets('the slideshow option shows when the renderer supports it', (
    tester,
  ) async {
    await tester.pumpWidget(_host(supported: true));
    await tester.pump();

    expect(find.textContaining('Slideshow'), findsOneWidget);
  });

  testWidgets('the slideshow option is hidden when it cannot run', (
    tester,
  ) async {
    // Offering a render the device cannot perform gets the user a failed
    // download and nothing else, so the option has to be absent rather than
    // disabled.
    await tester.pumpWidget(_host(supported: false));
    await tester.pump();

    expect(find.textContaining('Slideshow'), findsNothing);
  });

  testWidgets('a hidden slideshow is not downloaded either', (tester) async {
    // Hiding the row is not enough on its own: the download button submits the
    // selection, and a slideshow left in it would still reach the renderer.
    List<VideoQualityOption>? submitted;
    await tester.pumpWidget(
      _host(supported: false, onDownload: (options) => submitted = options),
    );
    await tester.pump();

    final button = find.textContaining('Download');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.where((option) => option.needsRendering), isEmpty);
  });

  testWidgets('a supported slideshow is downloadable', (tester) async {
    List<VideoQualityOption>? submitted;
    await tester.pumpWidget(
      _host(supported: true, onDownload: (options) => submitted = options),
    );
    await tester.pump();

    final button = find.textContaining('Download');
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();

    expect(submitted, isNotNull);
    expect(submitted!.where((option) => option.needsRendering), hasLength(1));
  });

  testWidgets('the slideshow row fits a phone-width screen', (tester) async {
    // The 800px default test surface is wider than any phone and hides every
    // narrow-width overflow, which is how such bugs have reached users before.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final locale in const [Locale('en'), Locale('vi')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoResultCard(
                metadata: _metadata,
                selectedQuality: _image,
                onQualitySelected: (_) {},
                onDownload: (_) {},
                onPreview: () {},
                slideshowRenderer: const _Renderer(isSupported: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    }
  });
}
