import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/platform_file.dart';
import '../l10n/generated/app_localizations.dart';
import '../core/utils/quality_helper.dart';
import '../models/download_task.dart';
import '../models/video_metadata.dart';
import '../services/download_service.dart';
import '../services/extractors/registry.dart';
import '../services/storage_service.dart';

class DownloadProvider extends ChangeNotifier {
  DownloadProvider({
    DownloadService? downloadService,
    StorageService? storageService,
  }) : _downloadService = downloadService ?? DownloadService(),
       _storageService = storageService ?? StorageService() {
    _historyReady = _loadHistory();
  }

  final List<DownloadTask> _tasks = [];
  final DownloadService _downloadService;
  final StorageService _storageService;
  final Uuid _uuid = const Uuid();
  late final Future<void> _historyReady;
  final List<_QueuedDownload> _queue = [];
  int _runningDownloads = 0;
  Future<void> _persistenceTail = Future.value();

  static const int maxConcurrentDownloads = 3;

  bool _isDisposed = false;

  List<DownloadTask> get allTasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();
  List<DownloadTask> get pausedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.paused).toList();
  List<DownloadTask> get completedTasks => _tasks
      .where(
        (t) =>
            t.status == DownloadStatus.completed ||
            t.status == DownloadStatus.handedOff,
      )
      .toList();

  @override
  void dispose() {
    _isDisposed = true;
    for (final task in _tasks) {
      task.dispose();
    }
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  Future<void> _loadHistory() async {
    final loaded = await _storageService.loadHistory();
    for (final task in loaded) {
      // fromJson already demotes interrupted downloads to `failed`; give them a
      // message so the UI explains why they need a retry.
      if (task.status == DownloadStatus.failed && task.errorMessage == null) {
        task.errorMessage = 'download_interrupted';
      }
    }
    _tasks
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> _saveHistory() {
    final snapshot = _tasks
        .map((task) => DownloadTask.fromJson(task.toJson()))
        .toList(growable: false);
    _persistenceTail = _persistenceTail.then(
      (_) => _storageService.saveHistory(snapshot),
    );
    return _persistenceTail;
  }

  Future<DownloadTask> startNewDownload({
    required VideoMetadata metadata,
    required VideoQualityOption quality,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    final tasks = await startNewDownloads(
      metadata: metadata,
      qualities: [quality],
      l10n: l10n,
      autoSaveToGallery: autoSaveToGallery,
    );
    return tasks.first;
  }

  /// Finds selected media that already has a completed local or Gallery copy.
  /// The source option id is stable across re-analysis; older history entries
  /// fall back to quality and media kind when that id was not persisted.
  Future<List<DownloadTask>> findExistingDownloads({
    required VideoMetadata metadata,
    required List<VideoQualityOption> qualities,
  }) async {
    await _historyReady;
    return _tasks
        .where((task) {
          if (task.status != DownloadStatus.completed) return false;
          final hasCopy =
              task.isSavedToGallery ||
              (task.filePath != null &&
                  PlatformFileHelper.fileExists(task.filePath!));
          if (!hasCopy) return false;
          final sameSource =
              task.platform == metadata.platform &&
              (task.videoId == metadata.id ||
                  (task.originalUrl.isNotEmpty &&
                      task.originalUrl == metadata.originalUrl));
          if (!sameSource) return false;
          return qualities.any((quality) {
            if (task.sourceOptionId.isNotEmpty && quality.id.isNotEmpty) {
              return task.sourceOptionId == quality.id;
            }
            return task.qualityLabel == quality.label &&
                task.kind == quality.kind;
          });
        })
        .toList(growable: false);
  }

  Future<List<DownloadTask>> startNewDownloads({
    required VideoMetadata metadata,
    required List<VideoQualityOption> qualities,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    // Do not let the asynchronous history restore clear a task that the user
    // starts immediately after launch.
    await _historyReady;

    if (qualities.isEmpty) return [];
    final tasks = qualities
        .map(
          (quality) => DownloadTask(
            id: _uuid.v4(),
            videoId: metadata.id,
            title: quality.isImage
                ? '${metadata.title} - ${quality.label}'
                : metadata.title,
            author: metadata.author,
            thumbnailUrl: quality.isImage
                ? quality.thumbnailUrl ?? quality.downloadUrl
                : metadata.coverUrl,
            downloadUrl: quality.downloadUrl,
            originalUrl: metadata.originalUrl,
            platform: metadata.platform,
            sourceOptionId: quality.id,
            qualityLabel: quality.label,
            format: quality.format,
            kind: quality.kind,
            headers: quality.headers,
            totalBytes: quality.sizeBytes ?? 0,
          ),
        )
        .toList();

    _tasks.insertAll(0, tasks.reversed);
    notifyListeners();
    await _saveHistory();

    for (final task in tasks) {
      _queue.add(
        _QueuedDownload(
          task: task,
          l10n: l10n,
          autoSaveToGallery: autoSaveToGallery,
        ),
      );
    }
    _drainQueue();
    return tasks;
  }

  void _drainQueue() {
    while (_runningDownloads < maxConcurrentDownloads && _queue.isNotEmpty) {
      final queued = _queue.removeAt(0);
      if (queued.task.status != DownloadStatus.queued ||
          !_tasks.contains(queued.task)) {
        continue;
      }
      _runningDownloads++;
      unawaited(
        _executeDownload(
          queued.task,
          l10n: queued.l10n,
          autoSaveToGallery: queued.autoSaveToGallery,
        ).whenComplete(() {
          _runningDownloads--;
          _drainQueue();
        }),
      );
    }
  }

  Future<void> _executeDownload(
    DownloadTask task, {
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    await _downloadService.startDownload(
      task: task,
      l10n: l10n,
      autoSaveToGallery: autoSaveToGallery,
      onProgress: (changedTask, _, _, _, _) =>
          changedTask.notifyProgressChanged(),
      onComplete: (_, _) {
        notifyListeners();
        unawaited(_saveHistory());
      },
      onError: (_, _) {
        notifyListeners();
        unawaited(_saveHistory());
      },
    );
    // Covers the pause / cancel paths, which finish without a callback.
    notifyListeners();
    await _saveHistory();
  }

  void cancelTask(String taskId) {
    _queue.removeWhere((queued) => queued.task.id == taskId);
    _downloadService.cancelDownload(taskId);
    final task = _findTask(taskId);
    if (task == null) return;
    task.status = DownloadStatus.cancelled;
    task.downloadSpeed = 0.0;
    notifyListeners();
    unawaited(_saveHistory());
  }

  /// Suspends a running download, keeping the bytes already written.
  void pauseTask(String taskId) {
    final task = _findTask(taskId);
    if (task == null || task.status != DownloadStatus.downloading) return;
    if (_downloadService.pauseDownload(taskId)) {
      task.downloadSpeed = 0.0;
      notifyListeners();
    }
  }

  /// Continues a paused download, appending to the partial file when the source
  /// supports byte ranges.
  Future<void> resumeTask(
    DownloadTask task, {
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    if (task.status != DownloadStatus.paused) return;
    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    notifyListeners();
    _queue.add(
      _QueuedDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: autoSaveToGallery,
      ),
    );
    _drainQueue();
    await _saveHistory();
  }

  /// Retries a failed or cancelled task.
  ///
  /// Download URLs from YouTube, Facebook and Instagram carry short-lived
  /// signatures, so a stored URL is usually dead by the time a retry happens.
  /// The source link is re-extracted first and only falls back to the stored URL
  /// if that fails.
  Future<void> retryTask(
    DownloadTask task, {
    bool autoSaveToGallery = true,
    required AppLocalizations l10n,
  }) async {
    task.status = DownloadStatus.queued;
    task.progress = 0.0;
    task.receivedBytes = 0;
    task.downloadSpeed = 0.0;
    task.errorMessage = null;
    notifyListeners();

    if (task.filePath != null) {
      await PlatformFileHelper.deleteFile(task.filePath!);
    }

    final refreshedUrl = await _refreshDownloadUrl(task, l10n);
    if (refreshedUrl != null) {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      final refreshed = task.withRefreshedSource(
        downloadUrl: refreshedUrl.downloadUrl,
        headers: refreshedUrl.headers,
      );
      if (index != -1) {
        _tasks[index] = refreshed;
        task.dispose();
      }
      notifyListeners();
      _queue.add(
        _QueuedDownload(
          task: refreshed,
          l10n: l10n,
          autoSaveToGallery: autoSaveToGallery,
        ),
      );
      _drainQueue();
      await _saveHistory();
      return;
    }

    _queue.add(
      _QueuedDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: autoSaveToGallery,
      ),
    );
    _drainQueue();
    await _saveHistory();
  }

  /// Re-extracts [task]'s source link and returns the option matching the
  /// quality originally chosen, or null when re-extraction is not possible.
  Future<VideoQualityOption?> _refreshDownloadUrl(
    DownloadTask task,
    AppLocalizations l10n,
  ) async {
    if (task.originalUrl.isEmpty) return null;
    try {
      final metadata = await ExtractorRegistry.extract(task.originalUrl, l10n);
      if (task.sourceOptionId.isNotEmpty) {
        for (final option in metadata.qualities) {
          if (option.id == task.sourceOptionId) return option;
        }
      }
      for (final option in metadata.qualities) {
        if (option.label == task.qualityLabel) return option;
      }
      return QualityHelper.bestMatch(
        metadata.qualities,
        task.isAudioOnly ? 'Audio' : task.qualityLabel,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteTask(String taskId, {bool deleteLocalFile = true}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    _queue.removeWhere((queued) => queued.task.id == taskId);
    if (task.isActive || task.status == DownloadStatus.paused) {
      _downloadService.cancelDownload(taskId);
    }
    if (deleteLocalFile && task.filePath != null) {
      await PlatformFileHelper.deleteFile(task.filePath!);
    }
    _tasks.removeAt(index);
    task.dispose();
    notifyListeners();
    await _saveHistory();
  }

  /// Removes every finished entry, leaving running downloads alone.
  Future<void> clearFinished({bool deleteLocalFiles = false}) async {
    final finished = _tasks.where((t) => t.isDone).toList();
    for (final task in finished) {
      if (deleteLocalFiles && task.filePath != null) {
        await PlatformFileHelper.deleteFile(task.filePath!);
      }
    }
    _tasks.removeWhere((t) => t.isDone);
    for (final task in finished) {
      task.dispose();
    }
    notifyListeners();
    await _saveHistory();
  }

  /// Clears downloaded files and their finished history entries. Active and
  /// paused transfers are deliberately left alone; callers should disable the
  /// action while any transfer is in flight.
  Future<bool> clearDownloadedFiles() async {
    await _historyReady;
    if (_tasks.any(
      (task) => task.isActive || task.status == DownloadStatus.paused,
    )) {
      return false;
    }
    await _storageService.clearDownloads();
    final finished = _tasks.where((task) => task.isDone).toList();
    _tasks.removeWhere((task) => task.isDone);
    for (final task in finished) {
      task.dispose();
    }
    notifyListeners();
    await _saveHistory();
    return true;
  }

  Future<bool> saveToGalleryManually(DownloadTask task) async {
    if (task.filePath == null) return false;
    final success = await _storageService.saveToGallery(
      task.filePath!,
      isAudio: task.isAudioOnly,
      isImage: task.isImage,
    );
    if (success) {
      task.isSavedToGallery = true;
      notifyListeners();
      await _saveHistory();
    }
    return success;
  }

  Future<void> openFile(DownloadTask task) async {
    if (task.filePath == null) return;
    await _downloadService.openFile(task.filePath!);
  }

  Future<void> shareFile(DownloadTask task, String message) async {
    if (task.filePath == null) return;
    await _downloadService.shareFile(task.filePath!, text: message);
  }

  DownloadTask? _findTask(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}

class _QueuedDownload {
  const _QueuedDownload({
    required this.task,
    required this.l10n,
    required this.autoSaveToGallery,
  });

  final DownloadTask task;
  final AppLocalizations l10n;
  final bool autoSaveToGallery;
}
