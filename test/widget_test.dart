import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_video/core/utils/formatters.dart';
import 'package:snap_video/core/utils/url_helper.dart';
import 'package:snap_video/models/video_platform.dart';
import 'package:snap_video/providers/download_provider.dart';
import 'package:snap_video/providers/settings_provider.dart';
import 'package:snap_video/providers/video_extractor_provider.dart';
import 'package:snap_video/views/home/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('UrlHelper Tests', () {
    test('Detect YouTube URLs', () {
      expect(
        UrlHelper.detectPlatform('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        VideoPlatform.youtube,
      );
      expect(
        UrlHelper.detectPlatform('https://youtu.be/dQw4w9WgXcQ'),
        VideoPlatform.youtube,
      );
      expect(
        UrlHelper.detectPlatform('https://youtube.com/shorts/abc123xyz'),
        VideoPlatform.youtube,
      );
    });

    test('Detect TikTok URLs', () {
      expect(
        UrlHelper.detectPlatform('https://www.tiktok.com/@user/video/1234567890'),
        VideoPlatform.tiktok,
      );
      expect(
        UrlHelper.detectPlatform('https://vm.tiktok.com/ZMxxxx/'),
        VideoPlatform.tiktok,
      );
    });

    test('Detect Facebook URLs', () {
      expect(
        UrlHelper.detectPlatform('https://www.facebook.com/watch?v=123456'),
        VideoPlatform.facebook,
      );
      expect(
        UrlHelper.detectPlatform('https://fb.watch/abcdef/'),
        VideoPlatform.facebook,
      );
    });

    test('Detect Twitter / X URLs', () {
      expect(
        UrlHelper.detectPlatform('https://x.com/user/status/1234567890'),
        VideoPlatform.twitter,
      );
      expect(
        UrlHelper.detectPlatform('https://twitter.com/user/status/1234567890'),
        VideoPlatform.twitter,
      );
    });

    test('Extract clean URL from shared text', () {
      const raw = 'Check out this awesome video https://youtu.be/dQw4w9WgXcQ from YouTube!';
      expect(
        UrlHelper.extractCleanUrl(raw),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });
  });

  group('Formatters Tests', () {
    test('Format bytes correctly', () {
      expect(Formatters.formatBytes(0), '0 B');
      expect(Formatters.formatBytes(1024), '1.0 KB');
      expect(Formatters.formatBytes(1048576), '1.0 MB');
      expect(Formatters.formatBytes(1073741824), '1.0 GB');
    });

    test('Format duration correctly', () {
      expect(Formatters.formatDuration(const Duration(minutes: 3, seconds: 45)), '03:45');
      expect(Formatters.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '01:02:03');
    });
  });

  testWidgets('HomeScreen smoke test', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});

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

    expect(find.text('SnapVideo'), findsOneWidget);
    expect(find.text('Dán liên kết video'), findsOneWidget);
    expect(find.text('Phân tích & Tải video'), findsOneWidget);
  });
}
