import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/views/downloads/downloads_screen.dart';
import 'package:nimble_clip/views/downloads/widgets/active_download_card.dart';
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

/// Serves a fixed history so a screen can be rendered with real tasks in it.
class _SeededHistoryRepository implements DownloadHistoryRepository {
  _SeededHistoryRepository(Iterable<DownloadTask> tasks)
    : _seed = tasks.map((task) => task.toJson()).toList();

  final List<Map<String, dynamic>> _seed;

  @override
  Future<List<DownloadTask>> loadHistory() async =>
      _seed.map(DownloadTask.fromJson).toList();

  @override
  Future<List<DownloadTask>> loadDownloadReceipts() async => [];

  @override
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots) async {}

  @override
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) async {}

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {}

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {}
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

  group('ActiveDownloadCard', () {
    testWidgets('a progress tick does not rebuild the static header', (
      tester,
    ) async {
      final task = DownloadTask(
        id: 'task-1',
        videoId: 'video',
        title: 'Clip',
        author: 'Creator',
        thumbnailUrl: 'https://cdn.example.com/thumb.jpg',
        downloadUrl: 'https://cdn.example.com/clip.mp4',
        originalUrl: 'https://example.com/post',
        platform: VideoPlatform.facebook,
        qualityLabel: 'HD 720p',
        status: DownloadStatus.downloading,
        totalBytes: 1000,
      );
      addTearDown(task.dispose);

      await tester.pumpWidget(
        _host(
          ActiveDownloadCard(task: task, onCancel: () {}),
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
        ),
      );
      await tester.pump();

      CachedNetworkImage thumbnail() =>
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      final before = thumbnail();

      // A running download notifies roughly ten times a second. The thumbnail
      // and title do not change with progress, so they must not be rebuilt.
      task
        ..receivedBytes = 500
        ..progress = 0.5
        ..notifyProgressChanged();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.textContaining('50%'), findsOneWidget);
      expect(identical(thumbnail(), before), isTrue);
    });
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

    testWidgets('each list entry is keyed by its task id', (tester) async {
      final tasks = [
        DownloadTask(
          id: 'running',
          videoId: 'v1',
          title: 'Running clip',
          author: 'Creator',
          thumbnailUrl: '',
          downloadUrl: 'https://cdn.example.com/1.mp4',
          originalUrl: 'https://example.com/1',
          platform: VideoPlatform.facebook,
          qualityLabel: 'HD 720p',
          status: DownloadStatus.paused,
        ),
        DownloadTask(
          id: 'finished',
          videoId: 'v2',
          title: 'Finished clip',
          author: 'Creator',
          thumbnailUrl: '',
          downloadUrl: 'https://cdn.example.com/2.mp4',
          originalUrl: 'https://example.com/2',
          platform: VideoPlatform.instagram,
          qualityLabel: 'HD 720p',
          status: DownloadStatus.completed,
        ),
      ];

      await tester.pumpWidget(
        _host(
          DownloadsScreen(onNavigateHome: () {}),
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(
              create: (_) => DownloadProvider(
                downloadService: _InertDownloadService(),
                historyRepository: _SeededHistoryRepository(tasks),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // Without stable keys, inserting a new task at the top of the list makes
      // Flutter reuse each element for a different task.
      expect(find.byKey(const ValueKey('download-running')), findsWidgets);
      expect(find.byKey(const ValueKey('download-finished')), findsWidgets);
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
