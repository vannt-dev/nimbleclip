import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/storage_service.dart';

class _ControlledDownloadService implements DownloadService {
  final Map<String, Completer<void>> pending = {};
  final List<String> started = [];
  int running = 0;
  int maxRunning = 0;

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
    running++;
    maxRunning = running > maxRunning ? running : maxRunning;
    task.status = DownloadStatus.downloading;
    final completer = Completer<void>();
    pending[task.id] = completer;
    await completer.future;
    pending.remove(task.id);
    running--;
    task
      ..status = DownloadStatus.completed
      ..progress = 1
      ..completedAt = DateTime.now();
    onComplete(task, '/tmp/${task.id}.jpg');
  }

  void finish(String id) => pending[id]?.complete();

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorageService implements StorageService {
  List<DownloadTask> history = [];
  bool downloadsCleared = false;
  int concurrentSaves = 0;
  int maxConcurrentSaves = 0;

  @override
  Future<List<DownloadTask>> loadHistory() async => [];

  @override
  Future<void> saveHistory(List<DownloadTask> tasks) async {
    concurrentSaves++;
    maxConcurrentSaves = concurrentSaves > maxConcurrentSaves
        ? concurrentSaves
        : maxConcurrentSaves;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    history = tasks
        .map((task) => DownloadTask.fromJson(task.toJson()))
        .toList();
    concurrentSaves--;
  }

  @override
  Future<void> clearDownloads() async {
    downloadsCleared = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VideoMetadata _metadata(int count) => VideoMetadata(
  id: 'post',
  originalUrl: 'https://example.com/post',
  title: 'Post',
  author: 'Author',
  coverUrl: '',
  platform: VideoPlatform.instagram,
  qualities: List.generate(
    count,
    (index) => VideoQualityOption(
      id: 'image-${index + 1}',
      label: 'Image ${index + 1}',
      quality: 'Image ${index + 1}',
      format: 'jpg',
      downloadUrl: 'https://cdn.example.com/${index + 1}.jpg',
      kind: MediaKind.image,
    ),
  ),
);

Future<void> _flush() async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test(
    'queue caps concurrency globally and skips a cancelled queued task',
    () async {
      final downloads = _ControlledDownloadService();
      final storage = _MemoryStorageService();
      final provider = DownloadProvider(
        downloadService: downloads,
        storageService: storage,
      );

      final tasks = await provider.startNewDownloads(
        metadata: _metadata(5),
        qualities: _metadata(5).qualities,
        l10n: l10n,
        autoSaveToGallery: false,
      );
      await _flush();

      expect(downloads.started, hasLength(3));
      expect(downloads.maxRunning, DownloadProvider.maxConcurrentDownloads);

      provider.cancelTask(tasks[3].id);
      for (final id in downloads.started.toList()) {
        downloads.finish(id);
      }
      await _waitUntil(() => downloads.started.contains(tasks[4].id));

      expect(downloads.started, contains(tasks[4].id));
      expect(downloads.started, isNot(contains(tasks[3].id)));
      downloads.finish(tasks[4].id);
      await _flush();
      expect(downloads.maxRunning, DownloadProvider.maxConcurrentDownloads);
      expect(storage.maxConcurrentSaves, 1);
    },
  );

  test('clear downloaded files also clears finished history', () async {
    final downloads = _ControlledDownloadService();
    final storage = _MemoryStorageService();
    final provider = DownloadProvider(
      downloadService: downloads,
      storageService: storage,
    );
    final metadata = _metadata(1);
    final tasks = await provider.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      autoSaveToGallery: false,
    );
    downloads.finish(tasks.single.id);
    await _flush();

    expect(await provider.clearDownloadedFiles(), isTrue);
    expect(storage.downloadsCleared, isTrue);
    expect(provider.allTasks, isEmpty);
  });

  test('clear downloaded files is rejected while a task is active', () async {
    final downloads = _ControlledDownloadService();
    final storage = _MemoryStorageService();
    final provider = DownloadProvider(
      downloadService: downloads,
      storageService: storage,
    );
    final metadata = _metadata(1);
    final tasks = await provider.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      autoSaveToGallery: false,
    );

    expect(await provider.clearDownloadedFiles(), isFalse);
    expect(storage.downloadsCleared, isFalse);
    downloads.finish(tasks.single.id);
  });
}
