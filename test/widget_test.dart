import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/core/utils/formatters.dart';
import 'package:nimble_clip/main.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';
import 'package:nimble_clip/providers/shared_intent_provider.dart';
import 'package:nimble_clip/core/utils/external_service_policy.dart';
import 'package:nimble_clip/services/extractors/base_extractor.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';
import 'package:nimble_clip/services/extractors/facebook_extractor.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/views/home/home_screen.dart';
import 'package:nimble_clip/views/home/widgets/video_result_card.dart';
import 'package:nimble_clip/views/downloads/widgets/completed_download_card.dart';

class _FixtureExtractorRegistry extends ExtractorRegistry {
  _FixtureExtractorRegistry(this.metadata);

  final VideoMetadata metadata;

  @override
  Future<VideoMetadata> extract(String rawUrl) async => metadata;
}

class _FailingExtractorRegistry extends ExtractorRegistry {
  _FailingExtractorRegistry(this.error);

  final Object error;

  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    throw error;
  }
}

class _ConcurrentFixtureRegistry extends ExtractorRegistry {
  int active = 0;
  int maximumActive = 0;

  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    active++;
    if (active > maximumActive) maximumActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    active--;
    return VideoMetadata(
      id: rawUrl,
      originalUrl: rawUrl,
      title: rawUrl,
      author: 'Fixture',
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption.video(
          id: rawUrl,
          label: const Hd720(),
          quality: '720p',
          format: 'mp4',
          downloadUrl: '$rawUrl/video.mp4',
        ),
      ],
    );
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('ExtractorRegistry routing', () {
    final registry = ExtractorRegistry();

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
        expect(registry.getExtractorFor(url).platform, platform, reason: url);
      });
    });

    test('every platform except generic has an extractor registered', () {
      final registered = registry.extractors.map((e) => e.platform).toSet();
      expect(registered, containsAll(VideoPlatform.values));
    });

    test('the catch-all extractor is last', () {
      expect(registry.extractors.last.platform, VideoPlatform.generic);
    });

    test('rejects a non-http link before touching the network', () async {
      await expectLater(
        registry.extract('not a url'),
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

    test('batch analysis is capped and uses bounded concurrency', () async {
      final registry = _ConcurrentFixtureRegistry();
      final provider = VideoExtractorProvider(extractorRegistry: registry);
      final urls = List.generate(
        25,
        (index) => 'https://example.com/post/$index',
      );

      final results = await provider.analyzeUrls(urls, l10n: l10n);

      expect(results, hasLength(VideoExtractorProvider.maximumBatchUrls));
      expect(
        registry.maximumActive,
        lessThanOrEqualTo(VideoExtractorProvider.maximumParallelAnalyses),
      );
      expect(results.first.url, urls.first);
      expect(results.last.url, urls[19]);
    });
  });

  // One test for the whole root on purpose: the native download gateway claims
  // a process-wide single-subscription stream, so a second NimbleClipApp in the
  // same test process cannot listen to it.
  testWidgets('the real app root builds and keeps one extractor registry', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const NimbleClipApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);

    final context = tester.element(find.byType(MaterialApp));
    final policy = Provider.of<ExtractionPolicy>(context, listen: false);
    final before = Provider.of<ExtractorRegistry>(context, listen: false);

    policy.setAllowExternalServices(false);
    await tester.pump();

    final after = Provider.of<ExtractorRegistry>(context, listen: false);
    expect(identical(before, after), isTrue);
    // The shared policy object is what the extractors read, so the new value
    // reaches them without the registry being rebuilt.
    final facebook = before.extractors.whereType<FacebookExtractor>().single;
    expect(facebook.externalServiceAccess.allowExternalServices, isFalse);
  });

  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => VideoExtractorProvider()),
          ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
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

  testWidgets('the home screen lays out on a phone in every locale', (
    tester,
  ) async {
    // The default 800px test surface is wider than any phone, which is what
    // let two horizontal overflows go unnoticed. Vietnamese matters here:
    // several of its strings are longer than the English ones.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final locale in const [Locale('en'), Locale('vi')]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => VideoExtractorProvider()),
            ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
            ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
            ChangeNotifierProvider(create: (_) => DownloadProvider()),
          ],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(onNavigateDownloads: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'locale $locale');
    }
  });

  test('an extraction failure reaches the UI as localized text', () async {
    final registry = _FailingExtractorRegistry(
      const ExtractionException(
        ExtractionFailure(ExtractionFailureKind.xNoVideo),
      ),
    );
    final provider = VideoExtractorProvider(extractorRegistry: registry);

    await provider.analyzeUrl('https://x.com/a/status/1', l10n: l10n);

    // The trap this guards: `_readableError` used to call `toString()`, which
    // after this change would surface `ExtractionFailureKind.xNoVideo`.
    expect(provider.errorMessage, l10n.xNoVideo);
    expect(provider.errorMessage, isNot(contains('ExtractionFailureKind')));
  });

  test('a non-extraction error still falls back to its message', () async {
    final registry = _FailingExtractorRegistry(Exception('network down'));
    final provider = VideoExtractorProvider(extractorRegistry: registry);

    await provider.analyzeUrl('https://x.com/a/status/1', l10n: l10n);

    expect(provider.errorMessage, 'network down');
  });

  testWidgets('the home image preview carries the source request headers', (
    WidgetTester tester,
  ) async {
    const quality = VideoQualityOption(
      id: 'fixture-image',
      label: ImageIndex(1),
      quality: 'Original',
      format: 'jpg',
      downloadUrl: 'https://cdn.example.com/photo.jpg',
      kind: MediaKind.image,
      headers: {'Referer': 'https://www.instagram.com/'},
    );
    const metadata = VideoMetadata(
      id: 'fixture',
      originalUrl: 'https://www.instagram.com/p/abc/',
      title: 'Fixture image',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.instagram,
      qualities: [quality],
    );
    final extractor = VideoExtractorProvider(
      extractorRegistry: _FixtureExtractorRegistry(metadata),
    );
    await extractor.analyzeUrl(metadata.originalUrl, l10n: l10n);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider.value(value: extractor),
          ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
          ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(onNavigateDownloads: () {}),
        ),
      ),
    );
    // The thumbnail placeholder spins forever, so settle is not reachable here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final preview = find.byIcon(Icons.zoom_in_rounded);
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final image = tester.widget<CachedNetworkImage>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(CachedNetworkImage),
      ),
    );
    // Instagram and Facebook CDNs reject image requests without a Referer, so
    // the preview has to send the same headers the download would.
    expect(image.httpHeaders, quality.headers);
    // An uncapped decode of a full-resolution post photo is the classic
    // out-of-memory path on low-RAM devices.
    expect(image.memCacheWidth, isNotNull);
  });

  testWidgets('new download action clears the result and focuses the URL', (
    WidgetTester tester,
  ) async {
    const quality = VideoQualityOption.video(
      id: 'fixture-video',
      label: Hd720(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://example.com/video.mp4',
    );
    const metadata = VideoMetadata(
      id: 'fixture',
      originalUrl: 'https://example.com/post',
      title: 'Fixture result',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [quality],
    );
    final extractor = VideoExtractorProvider(
      extractorRegistry: _FixtureExtractorRegistry(metadata),
    );
    await extractor.analyzeUrl(metadata.originalUrl, l10n: l10n);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider.value(value: extractor),
          ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
          ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
          ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(onNavigateDownloads: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('home-new-download'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(extractor.hasResult, isFalse);
    expect(find.text('Fixture result'), findsNothing);
    expect(find.text('Paste a video link'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );
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
        label: Hd720(),
        quality: '720p',
        format: 'mp4',
        downloadUrl: 'https://example.com/video-hd.mp4',
      );
      const sd = VideoQualityOption(
        id: 'video-sd',
        mediaId: 'video-1',
        label: Sd480(),
        quality: '480p',
        format: 'mp4',
        downloadUrl: 'https://example.com/video-sd.mp4',
      );
      const image1 = VideoQualityOption(
        id: 'image-1',
        mediaId: 'image-1',
        label: ImageIndex(1),
        quality: 'Original',
        format: 'jpg',
        downloadUrl: 'https://example.com/image-1.jpg',
        kind: MediaKind.image,
      );
      const image2 = VideoQualityOption(
        id: 'image-2',
        mediaId: 'image-2',
        label: ImageIndex(2),
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

  // Characterization tests for the parts of the result card the suite did not
  // reach. They pass against the current single-file widget and must keep
  // passing once it is split, which is what makes them a safety net.
  group('VideoResultCard', () {
    const hd = VideoQualityOption.video(
      id: 'v-hd',
      mediaId: 'v',
      label: Hd720(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn.example.com/v.mp4',
    );
    const audio = VideoQualityOption.audio(
      id: 'a-mp3',
      label: AudioMp3(null),
      quality: 'Audio',
      format: 'mp3',
      downloadUrl: 'https://cdn.example.com/a.mp3',
    );

    Widget host(
      VideoMetadata metadata, {
      ValueChanged<VideoQualityOption>? onSelected,
    }) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: VideoResultCard(
            metadata: metadata,
            selectedQuality: hd,
            onQualitySelected: onSelected ?? (_) {},
            onDownload: (_) {},
            onPreview: () {},
          ),
        ),
      ),
    );

    testWidgets('switching to the audio tab selects an audio option', (
      tester,
    ) async {
      const metadata = VideoMetadata(
        id: 'post',
        originalUrl: 'https://example.com/post',
        title: 'A clip',
        author: 'Creator',
        coverUrl: '',
        platform: VideoPlatform.youtube,
        qualities: [hd, audio],
      );
      VideoQualityOption? selected;

      await tester.pumpWidget(host(metadata, onSelected: (q) => selected = q));
      await tester.pump();

      expect(find.text('Video (1)'), findsOneWidget);
      expect(find.text('Audio (1)'), findsOneWidget);

      await tester.tap(find.text('Audio (1)'));
      await tester.pump();

      expect(selected, audio);
      expect(find.text('MP3 audio (Original sound)'), findsWidgets);
    });

    testWidgets('the summary shows title, author, duration and stats', (
      tester,
    ) async {
      const metadata = VideoMetadata(
        id: 'post',
        originalUrl: 'https://example.com/post',
        title: 'A memorable title',
        author: 'Some Creator',
        // The duration pill lives inside the thumbnail header, which only
        // renders when there is something to show a preview of.
        coverUrl: 'https://cdn.example.com/cover.jpg',
        platform: VideoPlatform.youtube,
        qualities: [hd],
        duration: Duration(minutes: 3, seconds: 7),
        viewCount: 1500,
        likeCount: 42,
      );

      await tester.pumpWidget(host(metadata));
      await tester.pump();

      expect(find.text('A memorable title'), findsOneWidget);
      expect(find.text('Some Creator'), findsOneWidget);
      expect(
        find.text(Formatters.formatDuration(metadata.duration)),
        findsOneWidget,
      );
      expect(find.text(Formatters.formatCount(1500)), findsOneWidget);
      expect(find.text(Formatters.formatCount(42)), findsOneWidget);
    });

    testWidgets('the tab row is hidden when there is no audio option', (
      tester,
    ) async {
      const metadata = VideoMetadata(
        id: 'post',
        originalUrl: 'https://example.com/post',
        title: 'Video only',
        author: 'Creator',
        coverUrl: '',
        platform: VideoPlatform.youtube,
        qualities: [hd],
      );

      await tester.pumpWidget(host(metadata));
      await tester.pump();

      expect(find.text('Video (1)'), findsNothing);
      expect(find.text('Audio (0)'), findsNothing);
      expect(find.text('HD 720p (High quality)'), findsWidgets);
    });
  });
}
