import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/services/storage_service.dart';

class _ControlledDownloadService implements DownloadGateway {
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

class _MemoryStorageService
    implements StorageService, DownloadHistoryRepository, MediaFileActions {
  List<DownloadTask> history = [];
  List<DownloadTask> receipts = [];
  bool downloadsCleared = false;
  bool? galleryExistsResult;
  int historySaveCount = 0;
  int concurrentSaves = 0;
  int maxConcurrentSaves = 0;

  @override
  Future<List<DownloadTask>> loadHistory() async =>
      history.map((task) => DownloadTask.fromJson(task.toJson())).toList();

  @override
  Future<void> saveHistory(List<DownloadTask> tasks) async {
    historySaveCount++;
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
  Future<List<DownloadTask>> loadDownloadReceipts() async =>
      receipts.map((task) => DownloadTask.fromJson(task.toJson())).toList();

  @override
  Future<void> saveDownloadReceipt(DownloadTask task) async {
    receipts.removeWhere((entry) => entry.id == task.id);
    receipts.add(DownloadTask.fromJson(task.toJson()));
  }

  @override
  Future<void> saveDownloadReceipts(Iterable<DownloadTask> tasks) async {
    for (final task in tasks) {
      await saveDownloadReceipt(task);
    }
  }

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {
    receipts.removeWhere((entry) => ids.contains(entry.id));
  }

  @override
  Future<bool?> galleryExists(String filePath, {required bool isImage}) async =>
      galleryExistsResult;

  @override
  bool exists(String filePath) => false;

  @override
  Future<void> clearDownloads() async {
    downloadsCleared = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DownloadProvider _provider(
  DownloadGateway downloads,
  _MemoryStorageService storage,
) => DownloadProvider(
  downloadService: downloads,
  storageService: storage,
  historyRepository: storage,
  fileActions: storage,
);

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
      final provider = _provider(downloads, storage);

      final tasks = await provider.startNewDownloads(
        metadata: _metadata(5),
        qualities: _metadata(5).qualities,
        l10n: l10n,
        options: const DownloadOptions(autoSaveToGallery: false),
      );
      await _flush();

      expect(downloads.started, hasLength(3));
      expect(downloads.maxRunning, provider.maxConcurrentDownloads);

      provider.cancelTask(tasks[3].id);
      for (final id in downloads.started.toList()) {
        downloads.finish(id);
      }
      await _waitUntil(() => downloads.started.contains(tasks[4].id));

      expect(downloads.started, contains(tasks[4].id));
      expect(downloads.started, isNot(contains(tasks[3].id)));
      downloads.finish(tasks[4].id);
      await _flush();
      expect(downloads.maxRunning, provider.maxConcurrentDownloads);
      expect(storage.maxConcurrentSaves, 1);
    },
  );

  test('clear downloaded files also clears finished history', () async {
    final downloads = _ControlledDownloadService();
    final storage = _MemoryStorageService();
    final provider = _provider(downloads, storage);
    final metadata = _metadata(1);
    final tasks = await provider.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    downloads.finish(tasks.single.id);
    await _flush();

    expect(await provider.clearDownloadedFiles(), isTrue);
    expect(storage.downloadsCleared, isTrue);
    expect(provider.allTasks, isEmpty);
  });

  test('persists history once when a download completes', () async {
    final downloads = _ControlledDownloadService();
    final storage = _MemoryStorageService();
    final provider = _provider(downloads, storage);
    final metadata = _metadata(1);
    final tasks = await provider.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    expect(storage.historySaveCount, 1);

    downloads.finish(tasks.single.id);
    await _flush();

    expect(storage.historySaveCount, 2);
    expect(storage.receipts, hasLength(1));
  });

  test('clear downloaded files is rejected while a task is active', () async {
    final downloads = _ControlledDownloadService();
    final storage = _MemoryStorageService();
    final provider = _provider(downloads, storage);
    final metadata = _metadata(1);
    final tasks = await provider.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );

    expect(await provider.clearDownloadedFiles(), isFalse);
    expect(storage.downloadsCleared, isFalse);
    downloads.finish(tasks.single.id);
  });

  test(
    'does not queue the same source option twice while it is active',
    () async {
      final downloads = _ControlledDownloadService();
      final provider = _provider(downloads, _MemoryStorageService());
      final metadata = _metadata(1);

      final first = await provider.startNewDownloads(
        metadata: metadata,
        qualities: metadata.qualities,
        l10n: l10n,
        options: const DownloadOptions(autoSaveToGallery: false),
      );
      final duplicate = await provider.startNewDownloads(
        metadata: metadata,
        qualities: metadata.qualities,
        l10n: l10n,
        options: const DownloadOptions(autoSaveToGallery: false),
      );

      expect(first, hasLength(1));
      expect(duplicate, isEmpty);
      expect(downloads.started, hasLength(1));
      downloads.finish(first.single.id);
    },
  );

  test(
    'marks a missing local file as failed and removes its receipt',
    () async {
      final metadata = _metadata(1);
      final missing = DownloadTask(
        id: 'missing-local',
        videoId: metadata.id,
        title: metadata.title,
        author: metadata.author,
        thumbnailUrl: '',
        downloadUrl: metadata.qualities.single.downloadUrl,
        originalUrl: metadata.originalUrl,
        platform: metadata.platform,
        sourceOptionId: metadata.qualities.single.id,
        qualityLabel: metadata.qualities.single.label,
        format: 'jpg',
        kind: MediaKind.image,
        status: DownloadStatus.completed,
        filePath: 'Z:/nimbleclip/definitely-missing.jpg',
      );
      final storage = _MemoryStorageService()
        ..history = [missing]
        ..receipts = [missing];
      final provider = _provider(_ControlledDownloadService(), storage);
      await _waitUntil(() => provider.allTasks.isNotEmpty);
      final restored = provider.allTasks.single;

      expect(await provider.ensureLocalFileAvailable(restored), isFalse);
      expect(restored.status, DownloadStatus.failed);
      expect(restored.errorMessage, 'local_file_missing');
      expect(restored.filePath, isNull);
      expect(storage.receipts, isEmpty);
    },
  );

  test('finds an already downloaded source option', () async {
    final metadata = _metadata(1);
    final existing = DownloadTask(
      id: 'existing',
      videoId: metadata.id,
      title: metadata.title,
      author: metadata.author,
      thumbnailUrl: '',
      downloadUrl: metadata.qualities.single.downloadUrl,
      originalUrl: metadata.originalUrl,
      platform: metadata.platform,
      sourceOptionId: metadata.qualities.single.id,
      qualityLabel: metadata.qualities.single.label,
      format: metadata.qualities.single.format,
      kind: metadata.qualities.single.kind,
      status: DownloadStatus.completed,
      isSavedToGallery: true,
    );
    final storage = _MemoryStorageService()..history = [existing];
    final provider = _provider(_ControlledDownloadService(), storage);

    final matches = await provider.findExistingDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
    );

    expect(matches, hasLength(1));
    expect(matches.single.id, existing.id);
  });

  test('finds a receipt after visible history was cleared', () async {
    final metadata = _metadata(1);
    final receipt = DownloadTask(
      id: 'receipt',
      videoId: metadata.id,
      title: metadata.title,
      author: metadata.author,
      thumbnailUrl: '',
      downloadUrl: metadata.qualities.single.downloadUrl,
      originalUrl: metadata.originalUrl,
      platform: metadata.platform,
      sourceOptionId: metadata.qualities.single.id,
      qualityLabel: metadata.qualities.single.label,
      format: 'jpg',
      kind: MediaKind.image,
      status: DownloadStatus.completed,
      filePath: '/deleted/local/receipt.jpg',
      isSavedToGallery: true,
    );
    final storage = _MemoryStorageService()
      ..receipts = [receipt]
      ..galleryExistsResult = true;
    final provider = _provider(_ControlledDownloadService(), storage);

    expect(
      await provider.findExistingDownloads(
        metadata: metadata,
        qualities: metadata.qualities,
      ),
      hasLength(1),
    );
  });

  test(
    'purges a receipt when both local and Gallery copies are gone',
    () async {
      final metadata = _metadata(1);
      final receipt = DownloadTask(
        id: 'stale',
        videoId: metadata.id,
        title: metadata.title,
        author: metadata.author,
        thumbnailUrl: '',
        downloadUrl: metadata.qualities.single.downloadUrl,
        originalUrl: metadata.originalUrl,
        platform: metadata.platform,
        sourceOptionId: metadata.qualities.single.id,
        qualityLabel: metadata.qualities.single.label,
        format: 'jpg',
        kind: MediaKind.image,
        status: DownloadStatus.completed,
        filePath: '/deleted/local/stale.jpg',
        isSavedToGallery: true,
      );
      final storage = _MemoryStorageService()
        ..receipts = [receipt]
        ..galleryExistsResult = false;
      final provider = _provider(_ControlledDownloadService(), storage);

      expect(
        await provider.findExistingDownloads(
          metadata: metadata,
          qualities: metadata.qualities,
        ),
        isEmpty,
      );
      expect(storage.receipts, isEmpty);
    },
  );
}
