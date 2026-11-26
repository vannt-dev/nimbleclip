import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/constants/app_constants.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/analysis_history_provider.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/providers/quick_download_coordinator.dart';
import 'package:nimble_clip/providers/settings_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/keep_alive.dart';
import 'package:nimble_clip/services/quick_share_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_storage.dart';

const _hd = VideoQualityOption.video(
  id: 'v-720',
  mediaId: 'v',
  label: Hd720(),
  quality: '720p',
  format: 'mp4',
  downloadUrl: 'https://cdn.example.com/clip-720.mp4',
);

const _sd = VideoQualityOption.video(
  id: 'v-480',
  mediaId: 'v',
  label: Sd480(),
  quality: '480p',
  format: 'mp4',
  downloadUrl: 'https://cdn.example.com/clip-480.mp4',
);

const _metadata = VideoMetadata(
  id: 'clip',
  originalUrl: 'https://www.tiktok.com/@creator/video/1',
  title: 'A clip',
  author: 'Creator',
  coverUrl: '',
  platform: VideoPlatform.tiktok,
  qualities: [_hd, _sd],
);

const _sharedText = 'Look at this https://www.tiktok.com/@creator/video/1';

class _FixtureRegistry extends ExtractorRegistry {
  _FixtureRegistry({this.failure});

  final Object? failure;
  final List<String> asked = [];

  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    asked.add(rawUrl);
    final error = failure;
    if (error != null) throw error;
    return _metadata;
  }
}

class _BrokenHistory extends AnalysisHistoryProvider {
  @override
  Future<void> add(VideoMetadata metadata) async => throw StateError('disk');
}

/// Records what Quick download tells the platform.
class _FakeChannel implements QuickShareChannel {
  final StreamController<String> incoming = StreamController<String>();
  final List<String> messages = [];
  final List<bool> targetStates = [];
  int releases = 0;

  @override
  Stream<String> get shares => incoming.stream;

  @override
  Future<void> setTargetEnabled(bool enabled) async =>
      targetStates.add(enabled);

  @override
  Future<void> showMessage(String message) async => messages.add(message);

  @override
  Future<void> releaseKeepAlive() async => releases++;

  @override
  Future<void> requestNotifications() async {}
}

class _RecordingKeepAlive implements ProcessKeepAlive {
  final List<String> calls = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> start({required String title, required String text}) async =>
      calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');
}

/// Holds each download open until the test finishes or fails it.
class _GatedDownloads implements DownloadGateway {
  _GatedDownloads(this.directory);

  final Directory directory;
  final Map<String, Completer<String?>> gates = {};
  final List<DownloadTask> started = [];

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    started.add(task);
    task.status = DownloadStatus.downloading;
    final gate = gates[task.id] = Completer<String?>();
    final error = await gate.future;
    // The real gateways set the outcome on the task before calling back.
    if (error != null) {
      task
        ..status = DownloadStatus.failed
        ..errorMessage = error;
      onError(task, error);
      return;
    }
    final file = File('${directory.path}/${task.id}.mp4')
      ..writeAsBytesSync(List<int>.filled(64, 1));
    task
      ..filePath = file.path
      ..status = DownloadStatus.completed
      ..progress = 1;
    onComplete(task, file.path);
  }

  void finish(DownloadTask task) => gates[task.id]!.complete(null);

  void fail(DownloadTask task) => gates[task.id]!.complete('network down');

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late _GatedDownloads gateway;
  late _FakeChannel channel;
  late _RecordingKeepAlive keepAlive;
  late DownloadProvider downloads;

  /// The test host has no gallery; the files stay in the app's folder.
  const noGallery = {AppConstants.keyAutoSaveGallery: false};

  setUp(() {
    SharedPreferences.setMockInitialValues(noGallery);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    directory = Directory.systemTemp.createTempSync('quick_download_');
    gateway = _GatedDownloads(directory);
    channel = _FakeChannel();
    keepAlive = _RecordingKeepAlive();
    final storage = MemoryStorage(directory);
    downloads = DownloadProvider(
      downloadService: gateway,
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      keepAlive: keepAlive,
      keepAliveLinger: Duration.zero,
    );
  });

  tearDown(() {
    downloads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  QuickDownloadCoordinator coordinator({
    SettingsProvider? settings,
    ExtractorRegistry? registry,
    AnalysisHistoryProvider? history,
  }) => QuickDownloadCoordinator(
    channel: channel,
    settings: settings ?? SettingsProvider(quickShare: channel),
    downloads: downloads,
    extractorRegistry: registry ?? _FixtureRegistry(),
    history: history,
    deviceLocale: () => const Locale('en'),
  );

  /// Waits, in real time, until [condition] holds.
  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Condition never held');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'a shared link downloads at the preferred quality and says so',
    () async {
      SharedPreferences.setMockInitialValues({
        ...noGallery,
        AppConstants.keyPreferredQuality: '480p',
      });
      final history = AnalysisHistoryProvider();
      final quick = coordinator(history: history);

      final outcome = quick.handle(_sharedText);
      await until(() => channel.messages.isNotEmpty);

      expect(gateway.started, hasLength(1));
      final task = gateway.started.single;
      expect(task.sourceOptionId, _sd.id);
      expect(channel.messages, ['Downloading A clip']);
      // Held while the transfer runs, not only while the link is read.
      expect(keepAlive.calls, ['start']);
      expect(history.entries.map((entry) => entry.originalUrl), [
        _metadata.originalUrl,
      ]);

      gateway.finish(task);
      expect(await outcome, QuickDownloadOutcome.saved);
      expect(channel.messages.last, 'Downloaded A clip');
      expect(downloads.completedTasks.single.id, task.id);
      await until(() => keepAlive.calls.length == 2);
      expect(keepAlive.calls, ['start', 'stop']);
      // The share entry's own hold was let go once the list held the process.
      expect(channel.releases, greaterThanOrEqualTo(1));
    },
  );

  test('a failed transfer is reported', () async {
    final quick = coordinator();

    final outcome = quick.handle(_sharedText);
    await until(() => channel.messages.isNotEmpty);
    gateway.fail(gateway.started.single);

    expect(await outcome, QuickDownloadOutcome.failed);
    expect(channel.messages.last, 'Download failed: A clip');
  });

  test('text without a link starts nothing', () async {
    final registry = _FixtureRegistry();
    final quick = coordinator(registry: registry);

    expect(await quick.handle('no link here'), QuickDownloadOutcome.noLink);
    expect(registry.asked, isEmpty);
    expect(gateway.started, isEmpty);
    expect(channel.messages, [
      'There is no link to download in what was shared',
    ]);
    expect(channel.releases, greaterThanOrEqualTo(1));
  });

  test('a link that cannot be read is reported with the reason', () async {
    final quick = coordinator(
      registry: _FixtureRegistry(failure: Exception('This post is private')),
    );

    expect(await quick.handle(_sharedText), QuickDownloadOutcome.unreadable);
    expect(gateway.started, isEmpty);
    expect(channel.messages.single, startsWith('Could not download this link'));
  });

  test('the same link shared twice downloads once', () async {
    final quick = coordinator();

    final first = quick.handle(_sharedText);
    await until(() => channel.messages.isNotEmpty);
    expect(
      await quick.handle(_sharedText),
      QuickDownloadOutcome.alreadyRunning,
    );
    expect(channel.messages.last, 'Already downloading: A clip');
    expect(gateway.started, hasLength(1));

    gateway.finish(gateway.started.single);
    await first;
    expect(await quick.handle(_sharedText), QuickDownloadOutcome.alreadySaved);
    expect(channel.messages.last, 'Already downloaded: A clip');
    expect(gateway.started, hasLength(1));
  });

  test('an unexpected failure is still reported', () async {
    final quick = coordinator(history: _BrokenHistory());

    expect(await quick.handle(_sharedText), QuickDownloadOutcome.failed);
    expect(channel.messages.single, startsWith('Could not download this link'));
    expect(gateway.started, isEmpty);
    expect(channel.releases, greaterThanOrEqualTo(1));
  });

  test('a playlist is left to the app', () async {
    final registry = _FixtureRegistry();
    final quick = coordinator(registry: registry);

    expect(
      await quick.handle(
        'https://www.youtube.com/playlist?list=PL590L5WQmH8fJ54F369BLDSqIwcs-TCfs',
      ),
      QuickDownloadOutcome.needsApp,
    );
    expect(registry.asked, isEmpty);
    expect(channel.messages.single, 'Open NimbleClip to download a playlist');
  });

  test('messages follow the language chosen in the app', () async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyLanguageCode: 'vi',
    });
    final quick = coordinator();

    await quick.handle('nothing to see');

    expect(
      channel.messages.single,
      'Nội dung được chia sẻ không có liên kết để tải',
    );
  });

  test('links arriving from the share entry are picked up', () async {
    final quick = coordinator()..start();

    channel.incoming.add(_sharedText);
    await until(() => channel.messages.isNotEmpty);

    expect(gateway.started, hasLength(1));
    gateway.finish(gateway.started.single);
    await until(() => channel.messages.length == 2);
    await quick.dispose();
  });
}
