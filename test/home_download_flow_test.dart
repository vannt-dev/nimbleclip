import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/l10n/quality_descriptor_text.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/providers/shared_intent_provider.dart';
import 'package:nimble_clip/providers/video_extractor_provider.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/views/home/home_screen.dart';
import 'package:nimble_clip/views/home/widgets/download_feedback.dart';

const _quality = VideoQualityOption.video(
  id: 'v-hd',
  mediaId: 'v',
  label: Hd720(),
  quality: '720p',
  format: 'mp4',
  downloadUrl: 'https://cdn.example.com/clip.mp4',
);

const _metadata = VideoMetadata(
  id: 'clip',
  originalUrl: 'https://www.youtube.com/watch?v=abc',
  title: 'A clip',
  author: 'Creator',
  coverUrl: '',
  platform: VideoPlatform.youtube,
  qualities: [_quality],
);

VideoMetadata _metadataTitled(String title) => VideoMetadata(
  id: _metadata.id,
  originalUrl: _metadata.originalUrl,
  title: title,
  author: _metadata.author,
  coverUrl: '',
  platform: _metadata.platform,
  qualities: const [_quality],
);

class _FixtureRegistry extends ExtractorRegistry {
  _FixtureRegistry([this.metadata = _metadata]);

  final VideoMetadata metadata;

  @override
  Future<VideoMetadata> extract(String rawUrl) async => metadata;
}

/// Records what was started without touching the network or the filesystem.
class _RecordingGateway implements DownloadGateway {
  final List<String> started = [];

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    started.add(task.id);
    task.status = DownloadStatus.downloading;
  }

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() {}
}

/// Serves a fixed history and reports every local file as present, so a seeded
/// completed task counts as an existing download.
class _SeededHistory implements DownloadHistoryRepository, MediaFileActions {
  _SeededHistory([Iterable<DownloadTask> tasks = const []])
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

  @override
  bool exists(String filePath) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _en = lookupAppLocalizations(const Locale('en'));

DownloadTask _completedTask() => DownloadTask(
  id: 'already-here',
  videoId: _metadata.id,
  title: _metadata.title,
  author: _metadata.author,
  thumbnailUrl: '',
  downloadUrl: _quality.downloadUrl,
  originalUrl: _metadata.originalUrl,
  platform: _metadata.platform,
  sourceOptionId: _quality.id,
  qualityLabel: describeQuality(_quality.label, _en),
  format: 'mp4',
  status: DownloadStatus.completed,
  filePath: '/downloads/already-here.mp4',
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required DownloadProvider downloads,
  VideoMetadata metadata = _metadata,
}) async {
  final extractor = VideoExtractorProvider(
    extractorRegistry: _FixtureRegistry(metadata),
  );
  await extractor.analyzeUrl(metadata.originalUrl, l10n: _en);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider.value(value: extractor),
        ChangeNotifierProvider(create: (_) => AnalysisHistoryProvider()),
        ChangeNotifierProvider(create: (_) => SharedIntentProvider()),
        ChangeNotifierProvider.value(value: downloads),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(onNavigateDownloads: () {}),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  /// Starts a download for a post titled [title] and returns how tall the
  /// resulting notification is.
  Future<double> snackBarHeightFor(WidgetTester tester, String title) async {
    await _pumpHome(
      tester,
      downloads: DownloadProvider(
        downloadService: _RecordingGateway(),
        historyRepository: _SeededHistory(),
      ),
      metadata: _metadataTitled(title),
    );

    final button = find.text('Download now');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    // Let the bar finish sliding in, or it is measured mid-animation.
    await tester.pump(const Duration(seconds: 1));

    final height = tester.getSize(find.byType(SnackBar)).height;

    // Tear the tree down so a second call starts without the previous bar
    // still animating out.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    return height;
  }

  testWidgets('a long title does not make the download notification taller', (
    tester,
  ) async {
    // The bar is a passing notice, not the download itself: it should stay the
    // same size whatever the post is called, rather than growing to four lines
    // and covering the page underneath.
    final short = await snackBarHeightFor(tester, 'A clip');
    final long = await snackBarHeightFor(
      tester,
      'Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film '
      'With A Rather Long Subtitle Attached To It As Well',
    );

    expect(long, short);
  });

  testWidgets('the download notification keeps its action on the same row', (
    tester,
  ) async {
    // Measured at phone width: at the default 800px test surface everything
    // fits on one row anyway, which is what hid this.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final downloads = DownloadProvider(
      downloadService: _RecordingGateway(),
      historyRepository: _SeededHistory(),
    );
    final task = DownloadTask(
      id: 'task',
      videoId: 'clip',
      title: 'A clip',
      author: 'Creator',
      thumbnailUrl: '',
      downloadUrl: _quality.downloadUrl,
      originalUrl: _metadata.originalUrl,
      platform: VideoPlatform.youtube,
      qualityLabel: describeQuality(_quality.label, _en),
      format: 'mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => DownloadFeedback.showStarted(
                  context,
                  provider: downloads,
                  tasks: [task],
                  title:
                      'Big Buck Bunny 60fps 4K - Official Blender '
                      'Foundation Short Film',
                  onViewProgress: () {},
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // One row of text beside its action. Anything taller means the action was
    // pushed onto a line of its own and the bar is covering the page.
    expect(tester.getSize(find.byType(SnackBar)).height, lessThan(80));
  });

  testWidgets('a fresh download starts and reports progress', (tester) async {
    final gateway = _RecordingGateway();
    final downloads = DownloadProvider(
      downloadService: gateway,
      historyRepository: _SeededHistory(),
    );
    await _pumpHome(tester, downloads: downloads);

    final button = find.text('Download now');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(gateway.started, hasLength(1));
    expect(find.textContaining('Downloading: A clip'), findsOneWidget);
    expect(find.text('View progress'), findsOneWidget);
  });

  testWidgets('an already downloaded file asks before downloading again', (
    tester,
  ) async {
    final gateway = _RecordingGateway();
    final downloads = DownloadProvider(
      downloadService: gateway,
      historyRepository: _SeededHistory([_completedTask()]),
      fileActions: _SeededHistory(),
    );
    await _pumpHome(tester, downloads: downloads);

    final button = find.text('Download now');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Already downloaded'), findsOneWidget);
    expect(gateway.started, isEmpty);
  });

  testWidgets('cancelling the duplicate prompt starts nothing', (tester) async {
    final gateway = _RecordingGateway();
    final downloads = DownloadProvider(
      downloadService: gateway,
      historyRepository: _SeededHistory([_completedTask()]),
      fileActions: _SeededHistory(),
    );
    await _pumpHome(tester, downloads: downloads);

    final button = find.text('Download now');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    // The dialog's exit transition has to finish before it leaves the tree.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Already downloaded'), findsNothing);
    expect(gateway.started, isEmpty);
  });

  testWidgets('confirming the duplicate prompt starts the download', (
    tester,
  ) async {
    final gateway = _RecordingGateway();
    final downloads = DownloadProvider(
      downloadService: gateway,
      historyRepository: _SeededHistory([_completedTask()]),
      fileActions: _SeededHistory(),
    );
    await _pumpHome(tester, downloads: downloads);

    final button = find.text('Download now');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Download again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(gateway.started, hasLength(1));
  });
}
