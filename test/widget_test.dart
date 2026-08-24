import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/core/utils/formatters.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/views/home/home_screen.dart';
import 'package:nimble_clip/views/home/widgets/video_result_card.dart';
import 'package:nimble_clip/views/downloads/widgets/completed_download_card.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('ExtractorRegistry routing', () {
    test('sends each link to the extractor that owns its platform', () {
      const expected = {
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ': VideoPlatform.youtube,
        'https://www.tiktok.com/@u/video/1': VideoPlatform.tiktok,
        'https://x.com/u/status/1': VideoPlatform.twitter,
        'https://www.facebook.com/watch?v=1': VideoPlatform.facebook,
        'https://www.instagram.com/reel/Cxyz/': VideoPlatform.instagram,
        'https://cdn.example.com/clip.mp4': VideoPlatform.generic,
      };

      expected.forEach((url, platform) {
        expect(
          ExtractorRegistry.getExtractorFor(url).platform,
          platform,
          reason: url,
        );
      });
    });

    test('every platform except generic has an extractor registered', () {
      final registered = ExtractorRegistry.extractors
          .map((e) => e.platform)
          .toSet();
      expect(registered, containsAll(VideoPlatform.values));
    });

    test('the catch-all extractor is last', () {
      expect(ExtractorRegistry.extractors.last.platform, VideoPlatform.generic);
    });

    test('rejects a non-http link before touching the network', () async {
      await expectLater(
        ExtractorRegistry.extract('not a url', l10n),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Formatters', () {
    test('formats bytes', () {
      expect(Formatters.formatBytes(0), '0 B');
      expect(Formatters.formatBytes(1024), '1.0 KB');
      expect(Formatters.formatBytes(1048576), '1.0 MB');
      expect(Formatters.formatBytes(1073741824), '1.0 GB');
    });

    test('formats duration', () {
      expect(
        Formatters.formatDuration(const Duration(minutes: 3, seconds: 45)),
        '03:45',
      );
      expect(
        Formatters.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        '01:02:03',
      );
    });
  });

  group('VideoExtractorProvider', () {
    test(
      'rejects an invalid URL without clearing into a loading state',
      () async {
        final provider = VideoExtractorProvider();
        final ok = await provider.analyzeUrl(
          'definitely not a link',
          l10n: l10n,
        );

        expect(ok, isFalse);
        expect(provider.isAnalyzing, isFalse);
        expect(provider.errorMessage, isNotNull);
        expect(provider.hasResult, isFalse);
      },
    );

    test('clear() resets every field', () {
      final provider = VideoExtractorProvider()..clear();
      expect(provider.metadata, isNull);
      expect(provider.selectedQuality, isNull);
      expect(provider.errorMessage, isNull);
      expect(provider.currentUrl, '');
    });
  });

  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => VideoExtractorProvider()),
          ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(onNavigateDownloads: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NimbleClip'), findsOneWidget);
    expect(find.text('Paste a video link'), findsOneWidget);
    expect(find.text('Analyze & Download'), findsOneWidget);
  });

  testWidgets('completed audio does not offer a fake gallery save action', (
    WidgetTester tester,
  ) async {
    final task = DownloadTask(
      id: 'audio-task',
      videoId: 'post',
      title: 'Audio clip',
      author: 'Author',
      thumbnailUrl: '',
      downloadUrl: 'https://example.com/audio.m4a',
      originalUrl: 'https://example.com/post',
      platform: VideoPlatform.generic,
      qualityLabel: 'Audio',
      format: 'm4a',
      kind: MediaKind.audio,
      status: DownloadStatus.completed,
      filePath: '/tmp/audio.m4a',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CompletedDownloadCard(
            task: task,
            onPlay: () {},
            onSaveGallery: () {},
            onShare: () {},
            onOpenExternal: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('Save'), findsNothing);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Open with'), findsOneWidget);
  });

  testWidgets(
    'mixed post downloads one video quality and every selected image',
    (WidgetTester tester) async {
      const hd = VideoQualityOption(
        id: 'video-hd',
        mediaId: 'video-1',
        label: 'HD',
        quality: '720p',
        format: 'mp4',
        downloadUrl: 'https://example.com/video-hd.mp4',
      );
      const sd = VideoQualityOption(
        id: 'video-sd',
        mediaId: 'video-1',
        label: 'SD',
        quality: '480p',
        format: 'mp4',
        downloadUrl: 'https://example.com/video-sd.mp4',
      );
      const image1 = VideoQualityOption(
        id: 'image-1',
        mediaId: 'image-1',
        label: 'Image 1',
        quality: 'Original',
        format: 'jpg',
        downloadUrl: 'https://example.com/image-1.jpg',
        kind: MediaKind.image,
      );
      const image2 = VideoQualityOption(
        id: 'image-2',
        mediaId: 'image-2',
        label: 'Image 2',
        quality: 'Original',
        format: 'webp',
        downloadUrl: 'https://example.com/image-2.webp',
        kind: MediaKind.image,
      );
      const metadata = VideoMetadata(
        id: 'mixed-post',
        originalUrl: 'https://x.com/user/status/1',
        title: 'Mixed post',
        author: 'Author',
        coverUrl: '',
        platform: VideoPlatform.twitter,
        qualities: [hd, sd, image1, image2],
      );
      List<VideoQualityOption>? submitted;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: VideoResultCard(
                metadata: metadata,
                selectedQuality: hd,
                onQualitySelected: (_) {},
                onDownload: (options) => submitted = options,
                onPreview: () {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download (3)'));
      expect(submitted, isNotNull);
      expect(submitted, hasLength(3));
      expect(submitted!.where((option) => !option.isImage), [hd]);
      expect(submitted!.where((option) => option.isImage), [image1, image2]);
    },
  );
}
