import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/views/downloads/downloads_screen.dart';
import 'package:nimble_clip/views/downloads/widgets/active_download_card.dart';
import 'package:nimble_clip/views/home/media_picker_screen.dart';
import 'package:nimble_clip/views/player/video_player_screen.dart';
import 'package:nimble_clip/views/settings/settings_screen.dart';

import 'support/inert_download_service.dart';

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

VideoQualityOption _image(String id, int index) => VideoQualityOption.image(
  id: id,
  mediaId: id,
  label: ImageIndex(index),
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
      final gateway = InertDownloadService();
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
                downloadService: InertDownloadService(),
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
      final gateway = InertDownloadService();
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
                  DownloadProvider(downloadService: InertDownloadService()),
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
                  DownloadProvider(downloadService: InertDownloadService()),
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

  group('MediaPickerScreen', () {
    testWidgets('starts from the given selection and can select them all', (
      tester,
    ) async {
      final options = [_image('a', 1), _image('b', 2), _image('c', 3)];
      await tester.pumpWidget(
        _host(
          MediaPickerScreen(
            options: options,
            initiallySelectedIds: const {'a'},
            title: 'Choose images:',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Choose images:'), findsWidgets);
      expect(find.text('Select all'), findsOneWidget);

      await tester.tap(find.text('Select all'));
      await tester.pump();

      expect(find.text('Deselect all'), findsOneWidget);
    });

    testWidgets('builds only the visible cells of a large post', (
      tester,
    ) async {
      // A highlight can hold far more media than fits on screen. The grid
      // must stay lazy: the quality list it replaced was a plain Column
      // inside a scroll view, whose build cost grew with every extra video.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final many = [
        for (var i = 1; i <= 200; i++)
          VideoQualityOption.video(
            id: 'v$i',
            mediaId: 'v$i',
            label: VideoIndex(i),
            quality: 'Original',
            format: 'mp4',
            downloadUrl: 'https://cdn.example.com/$i.mp4',
            thumbnailUrl: 'https://cdn.example.com/$i.jpg',
          ),
      ];

      await tester.pumpWidget(
        _host(
          MediaPickerScreen(
            options: many,
            initiallySelectedIds: many.map(MediaPickerScreen.keyOf).toSet(),
            title: 'Choose videos:',
          ),
        ),
      );
      await tester.pump();

      final built = tester.widgetList(find.byType(InkWell)).length;
      expect(built, lessThan(40), reason: 'built $built cells of 200');
    });

    testWidgets('checks a video by the id it shares with its qualities', (
      tester,
    ) async {
      // Two qualities of one video are one entry: checking it must not leave
      // the other quality behind as a second, invisible choice.
      const hd = VideoQualityOption.video(
        id: 'clip-hd',
        mediaId: 'clip',
        label: VideoIndex(1),
        quality: '720p',
        format: 'mp4',
        downloadUrl: 'https://cdn.example.com/hd.mp4',
      );

      await tester.pumpWidget(
        _host(
          const MediaPickerScreen(
            options: [hd],
            initiallySelectedIds: {},
            title: 'Choose videos:',
          ),
        ),
      );
      await tester.pump();

      expect(MediaPickerScreen.keyOf(hd), 'clip');

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
