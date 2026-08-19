import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/core/utils/formatters.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/views/home/home_screen.dart';

void main() {
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
        expect(ExtractorRegistry.getExtractorFor(url).platform, platform,
            reason: url);
      });
    });

    test('every platform except generic has an extractor registered', () {
      final registered =
          ExtractorRegistry.extractors.map((e) => e.platform).toSet();
      expect(registered, containsAll(VideoPlatform.values));
    });

    test('the catch-all extractor is last', () {
      expect(ExtractorRegistry.extractors.last.platform, VideoPlatform.generic);
    });

    test('rejects a non-http link before touching the network', () async {
      await expectLater(
        ExtractorRegistry.extract('not a url'),
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
        Formatters.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
    });
  });

  group('VideoExtractorProvider', () {
    test('rejects an invalid URL without clearing into a loading state', () async {
      final provider = VideoExtractorProvider();
      final ok = await provider.analyzeUrl('definitely not a link');

      expect(ok, isFalse);
      expect(provider.isAnalyzing, isFalse);
      expect(provider.errorMessage, isNotNull);
      expect(provider.hasResult, isFalse);
    });

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
          home: HomeScreen(onNavigateDownloads: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('NimbleClip'), findsOneWidget);
    expect(find.text('Dán liên kết video'), findsOneWidget);
    expect(find.text('Phân tích & Tải video'), findsOneWidget);
  });
}
