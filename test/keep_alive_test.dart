import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/audio/audio_converter.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/keep_alive.dart';
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/services/storage_service.dart';

/// Records what the provider asks of the system.
class _RecordingKeepAlive implements ProcessKeepAlive {
  _RecordingKeepAlive({this.supported = true});

  final bool supported;
  final List<String> calls = [];

  @override
  bool get isSupported => supported;

  @override
  Future<void> start({required String title, required String text}) async {
    calls.add('start: $title');
  }

  @override
  Future<void> stop() async => calls.add('stop');
}

/// Holds each download open until the test lets it finish.
class _GatedDownloads implements DownloadGateway {
  _GatedDownloads(this.directory);

  final Directory directory;
  final Map<String, Completer<void>> gates = {};

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    task.status = DownloadStatus.downloading;
    await (gates[task.videoId] = Completer<void>()).future;
    final file = File('${directory.path}/${task.id}.${task.format}');
    await file.writeAsBytes(List.filled(16, 1));
    task
      ..filePath = file.path
      ..status = DownloadStatus.completed
      ..progress = 1;
    onComplete(task, file.path);
  }

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage
    implements StorageService, DownloadHistoryRepository, MediaFileActions {
  @override
  Future<List<DownloadTask>> loadHistory() async => [];

  @override
  Future<List<DownloadTask>> loadDownloadReceipts() async => [];

  @override
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots) async {}

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {}

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) async {}

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatedConverter implements AudioConverter {
  final Completer<void> gate = Completer<void>();
  bool started = false;

  @override
  bool get isSupported => true;

  @override
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    started = true;
    await gate.future;
    await File(outputPath).writeAsBytes(List.filled(8, 2));
    return outputPath;
  }

  @override
  Future<void> cancel(String jobId) async {}
}

VideoMetadata _post(String id, {bool audio = false}) => VideoMetadata(
  id: id,
  originalUrl: 'https://example.com/$id',
  title: 'Post $id',
  author: 'Author',
  coverUrl: '',
  platform: VideoPlatform.generic,
  qualities: [
    if (audio)
      VideoQualityOption.audio(
        id: 'audio',
        label: const AudioM4a(128),
        quality: 'Audio',
        format: 'm4a',
        downloadUrl: 'https://cdn.example.com/$id.m4a',
      )
    else
      VideoQualityOption(
        id: 'video',
        label: const ImageIndex(1),
        quality: '720p',
        format: 'mp4',
        downloadUrl: 'https://cdn.example.com/$id.mp4',
      ),
  ],
);

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// The process is kept working for as long as the app has a download to
/// finish, and only then: the notification that comes with it is a cost.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late Directory directory;
  late _GatedDownloads downloads;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('nimbleclip_keep_alive');
    downloads = _GatedDownloads(directory);
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  DownloadProvider provider(
    ProcessKeepAlive keepAlive, {
    Duration linger = Duration.zero,
    AudioConverter? converter,
  }) {
    final storage = _Storage();
    return DownloadProvider(
      downloadService: downloads,
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      audioConverter: converter,
      slideshowWorkspace: () async => directory,
      keepAlive: keepAlive,
      keepAliveLinger: linger,
    );
  }

  Future<DownloadTask> start(
    DownloadProvider provider,
    VideoMetadata post,
  ) async {
    final tasks = await provider.startNewDownloads(
      metadata: post,
      qualities: post.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    await _until(() => downloads.gates.containsKey(post.id));
    return tasks.single;
  }

  test('is asked for when a download starts and let go when it ends', () async {
    final keepAlive = _RecordingKeepAlive();
    final downloadProvider = provider(keepAlive);
    final task = await start(downloadProvider, _post('one'));

    expect(keepAlive.calls, ['start: ${l10n.keepAliveTitle}']);

    downloads.gates['one']!.complete();
    await _until(() => keepAlive.calls.length == 2);
    expect(task.status, DownloadStatus.completed);
    expect(keepAlive.calls.last, 'stop');
    downloadProvider.dispose();
  });

  test('is asked for once however many downloads overlap', () async {
    final keepAlive = _RecordingKeepAlive();
    final downloadProvider = provider(keepAlive);
    await start(downloadProvider, _post('one'));
    await start(downloadProvider, _post('two'));

    downloads.gates['one']!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(keepAlive.calls, hasLength(1), reason: 'one is still running');

    downloads.gates['two']!.complete();
    await _until(() => keepAlive.calls.length == 2);
    expect(keepAlive.calls, ['start: ${l10n.keepAliveTitle}', 'stop']);
    downloadProvider.dispose();
  });

  test('stays through the conversion that follows an audio download', () async {
    final keepAlive = _RecordingKeepAlive();
    final converter = _GatedConverter();
    final downloadProvider = provider(keepAlive, converter: converter)
      ..convertAudioToMp3 = true;
    final task = await start(downloadProvider, _post('song', audio: true));

    downloads.gates['song']!.complete();
    await _until(() => converter.started);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(keepAlive.calls, hasLength(1), reason: 'converting is work too');

    converter.gate.complete();
    await _until(() => keepAlive.calls.length == 2);
    expect(task.format, 'mp3');
    downloadProvider.dispose();
  });

  test('is kept between one download and the next', () async {
    final keepAlive = _RecordingKeepAlive();
    final downloadProvider = provider(
      keepAlive,
      linger: const Duration(milliseconds: 300),
    );
    await start(downloadProvider, _post('one'));
    downloads.gates['one']!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    // Within the linger: taking the notification down and putting it up
    // again would be a flicker for nothing.
    await start(downloadProvider, _post('two'));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(keepAlive.calls, hasLength(1));

    downloads.gates['two']!.complete();
    await _until(() => keepAlive.calls.length == 2);
    expect(keepAlive.calls.last, 'stop');
    downloadProvider.dispose();
  });

  test('is let go when the provider goes while work is running', () async {
    final keepAlive = _RecordingKeepAlive();
    final downloadProvider = provider(keepAlive);
    await start(downloadProvider, _post('one'));

    downloadProvider.dispose();
    expect(keepAlive.calls.last, 'stop');
  });

  test('a platform without it is never asked', () async {
    final keepAlive = _RecordingKeepAlive(supported: false);
    final downloadProvider = provider(keepAlive);
    await start(downloadProvider, _post('one'));
    downloads.gates['one']!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(keepAlive.calls, isEmpty);
    downloadProvider.dispose();
  });
}
