import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/views/downloads/downloads_screen.dart';
import 'package:nimble_clip/views/home/image_picker_screen.dart';
import 'package:nimble_clip/views/player/video_player_screen.dart';
import 'package:nimble_clip/views/settings/settings_screen.dart';

/// Keeps the real native gateway — and its process-wide update stream — out of
/// widget tests.
class _InertDownloadService implements DownloadGateway {
  bool disposed = false;

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {}

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() => disposed = true;
}

Widget _host(Widget child, {List<SingleChildWidget> providers = const []}) {
  final app = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
  if (providers.isEmpty) return app;
  return MultiProvider(providers: providers, child: app);
}

VideoQualityOption _image(String id) => VideoQualityOption.image(
  id: id,
  mediaId: id,
  label: id,
  quality: 'Original',
  format: 'jpg',
  downloadUrl: 'https://cdn.example.com/$id.jpg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  group('DownloadsScreen', () {
    testWidgets('shows the empty state when nothing has been downloaded', (
      tester,
    ) async {
      final gateway = _InertDownloadService();
      await tester.pumpWidget(
        _host(
          DownloadsScreen(onNavigateHome: () {}),
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(
              create: (_) => DownloadProvider(downloadService: gateway),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Download manager'), findsOneWidget);
      expect(find.text('Your download list is empty'), findsOneWidget);
    });

    testWidgets('disposing the provider releases the gateway', (tester) async {
      final gateway = _InertDownloadService();
      await tester.pumpWidget(
        _host(
          DownloadsScreen(onNavigateHome: () {}),
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(
              create: (_) => DownloadProvider(downloadService: gateway),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(gateway.disposed, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(gateway.disposed, isTrue);
    });
  });

  group('SettingsScreen', () {
    // The screen is one long scroll view; a phone-sized viewport never builds
    // the lower sections, so give the tests room to see all of it at once.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('renders every settings section', (tester) async {
      useTallViewport(tester);
      await tester.pumpWidget(
        _host(
          const SettingsScreen(),
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(
              create: (_) =>
                  DownloadProvider(downloadService: _InertDownloadService()),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('Allow external extraction services'), findsOneWidget);
    });

    testWidgets('toggling auto-save to gallery updates the provider', (
      tester,
    ) async {
      useTallViewport(tester);
      final settings = SettingsProvider();
      await tester.pumpWidget(
        _host(
          const SettingsScreen(),
          providers: [
            ChangeNotifierProvider.value(value: settings),
            ChangeNotifierProvider(
              create: (_) =>
                  DownloadProvider(downloadService: _InertDownloadService()),
            ),
          ],
        ),
      );
      await tester.pump();

      final before = settings.autoSaveGallery;
      await tester.tap(find.text('Automatically save to gallery'));
      await tester.pump();

      expect(settings.autoSaveGallery, isNot(before));
    });
  });

  group('ImagePickerScreen', () {
    testWidgets('starts from the given selection and can select them all', (
      tester,
    ) async {
      final options = [_image('a'), _image('b'), _image('c')];
      await tester.pumpWidget(
        _host(
          ImagePickerScreen(
            options: options,
            initiallySelectedIds: const {'a'},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Choose images:'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();

      expect(find.text('Deselect all'), findsOneWidget);
    });
  });

  group('VideoPlayerScreen', () {
    testWidgets('reports a missing source instead of building a player', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const VideoPlayerScreen(title: 'Clip')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('No video source'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
