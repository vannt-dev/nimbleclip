import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
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

const _quality = VideoQualityOption.video(
  id: 'v-hd',
  mediaId: 'v',
  label: 'HD 720p',
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

class _FixtureRegistry extends ExtractorRegistry {
  @override
  Future<VideoMetadata> extract(String rawUrl, AppLocalizations l10n) async =>
      _metadata;
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
  qualityLabel: _quality.label,
  format: 'mp4',
  status: DownloadStatus.completed,
  filePath: '/downloads/already-here.mp4',
);

Future<void> _pumpHome(
  WidgetTester tester, {
  required DownloadProvider downloads,
}) async {
  final extractor = VideoExtractorProvider(
    extractorRegistry: _FixtureRegistry(),
  );
  await extractor.analyzeUrl(
    _metadata.originalUrl,
    l10n: lookupAppLocalizations(const Locale('en')),
  );

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
