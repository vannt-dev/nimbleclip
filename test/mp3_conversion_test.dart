import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/services/storage_service.dart';

/// Finishes every download at once, leaving a real file of the task's format.
class _FileDownloadService implements DownloadGateway {
  _FileDownloadService(this.directory);

  final Directory directory;
  final List<String> cancelled = [];

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    final file = File('${directory.path}/${task.id}.${task.format}');
    await file.writeAsBytes(List.filled(64, 1));
    task
      ..filePath = file.path
      ..status = DownloadStatus.completed
      ..progress = 1
      ..totalBytes = 64
      ..receivedBytes = 64
      ..completedAt = DateTime.now();
    onComplete(task, file.path);
  }

  @override
  void cancelDownload(String taskId) => cancelled.add(taskId);

  @override
  bool pauseDownload(String taskId) => false;

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
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) async {}

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {}

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {}

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Writes a small MP3 stand-in, or fails, or waits to be released.
class _FakeConverter implements AudioConverter {
  _FakeConverter({this.supported = true, this.failure});

  final bool supported;
  final AudioConversionFailureKind? failure;
  final List<String> sources = [];
  final List<String> cancelled = [];
  Completer<void>? gate;

  @override
  bool get isSupported => supported;

  @override
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    sources.add(sourcePath);
    onProgress?.call(0.5);
    await gate?.future;
    if (cancelled.contains(jobId)) {
      throw const AudioConversionException(
        AudioConversionFailureKind.cancelled,
      );
    }
    if (failure != null) throw AudioConversionException(failure!);
    await File(outputPath).writeAsBytes(List.filled(20, 2));
    return outputPath;
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    gate?.complete();
  }
}

VideoMetadata _post({String format = 'm4a', bool audio = true}) =>
    VideoMetadata(
      id: 'post',
      originalUrl: 'https://example.com/post',
      title: 'Song',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.youtube,
      qualities: [
        if (audio)
          VideoQualityOption.audio(
            id: 'audio',
            label: const AudioM4a(128),
            quality: 'Audio',
            format: format,
            downloadUrl: 'https://cdn.example.com/a.$format',
          )
        else
          VideoQualityOption(
            id: 'video',
            label: const ImageIndex(1),
            quality: '720p',
            format: format,
            downloadUrl: 'https://cdn.example.com/v.$format',
          ),
      ],
    );

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('nimbleclip_mp3_test');
  });
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<(DownloadProvider, DownloadTask, List<DownloadStatus>)> download(
    _FakeConverter converter, {
    VideoMetadata? metadata,
    bool setting = true,
  }) async {
    final storage = _Storage();
    final provider = DownloadProvider(
      downloadService: _FileDownloadService(directory),
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      audioConverter: converter,
      slideshowWorkspace: () async => directory,
    )..convertAudioToMp3 = setting;
    final post = metadata ?? _post();
    final seen = <DownloadStatus>[];
    late DownloadTask task;
    final tasks = await provider.startNewDownloads(
      metadata: post,
      qualities: post.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    task = tasks.single;
    provider.addListener(() => seen.add(task.status));
    return (provider, task, seen);
  }

  test('an audio download is converted and replaced by the MP3', () async {
    final converter = _FakeConverter()..gate = Completer<void>();
    final (provider, task, seen) = await download(converter);
    await _settle();

    // Still converting: the fetched file is whole, but the task is not done.
    expect(task.status, DownloadStatus.downloading);
    expect(task.progress, 0.5);
    expect(seen, isNot(contains(DownloadStatus.completed)));
    final fetched = converter.sources.single;
    expect(fetched, endsWith('.m4a'));

    converter.gate!.complete();
    await _settle();

    expect(task.status, DownloadStatus.completed);
    expect(task.progress, 1);
    expect(task.format, 'mp3');
    expect(task.filePath, endsWith('.mp3'));
    expect(task.totalBytes, 20);
    expect(task.errorMessage, isNull);
    expect(File(task.filePath!).existsSync(), isTrue);
    expect(File(fetched).existsSync(), isFalse);
    expect(provider.canConvertAudioToMp3, isTrue);
  });

  test('nothing is converted unless it is wanted and needed', () async {
    for (final (converter, metadata, setting) in [
      (_FakeConverter(), _post(), false),
      (_FakeConverter(), _post(format: 'mp3'), true),
      (_FakeConverter(), _post(format: 'mp4', audio: false), true),
      (_FakeConverter(supported: false), _post(), true),
    ]) {
      final (_, task, _) = await download(
        converter,
        metadata: metadata,
        setting: setting,
      );
      await _settle();

      expect(converter.sources, isEmpty);
      expect(task.status, DownloadStatus.completed);
      expect(task.format, metadata.qualities.single.format);
      expect(File(task.filePath!).existsSync(), isTrue);
    }
  });

  test('a failed conversion keeps the fetched file and says so', () async {
    final converter = _FakeConverter(
      failure: AudioConversionFailureKind.failed,
    );
    final (_, task, _) = await download(converter);
    await _settle();

    expect(task.status, DownloadStatus.completed);
    expect(task.format, 'm4a');
    expect(task.filePath, endsWith('.m4a'));
    expect(File(task.filePath!).existsSync(), isTrue);
    expect(task.errorMessage, l10n.mp3ConversionFailed);
  });

  test('a cancel during the conversion removes the download', () async {
    final converter = _FakeConverter()..gate = Completer<void>();
    final (provider, task, _) = await download(converter);
    await _settle();
    final fetched = converter.sources.single;

    provider.cancelTask(task.id);
    await _settle();

    expect(converter.cancelled, [task.id]);
    expect(task.status, DownloadStatus.cancelled);
    expect(task.filePath, isNull);
    expect(File(fetched).existsSync(), isFalse);
    expect(directory.listSync().whereType<File>(), isEmpty);
  });
}
