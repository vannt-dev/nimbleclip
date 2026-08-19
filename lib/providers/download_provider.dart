import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/platform_file.dart';
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
  })  : _downloadService = downloadService ?? DownloadService(),
        _storageService = storageService ?? StorageService() {
    _historyReady = _loadHistory();
  }

  final List<DownloadTask> _tasks = [];
  final DownloadService _downloadService;
  final StorageService _storageService;
  final Uuid _uuid = const Uuid();
  late final Future<void> _historyReady;

  /// Progress callbacks arrive far faster than the screen refreshes; coalescing
  /// them into one notification per frame budget keeps the list from rebuilding
  /// hundreds of times a second during a download.
  static const Duration _progressNotifyInterval = Duration(milliseconds: 100);
  DateTime _lastProgressNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pendingProgressNotify;
  bool _isDisposed = false;

  List<DownloadTask> get allTasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks => _tasks.where((t) => t.isActive).toList();
  List<DownloadTask> get pausedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.paused).toList();
  List<DownloadTask> get completedTasks =>
      _tasks
          .where((t) =>
              t.status == DownloadStatus.completed ||
              t.status == DownloadStatus.handedOff)
          .toList();

  @override
  void dispose() {
    _isDisposed = true;
    _pendingProgressNotify?.cancel();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  void _notifyProgress() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastProgressNotify);
    if (elapsed >= _progressNotifyInterval) {
      _lastProgressNotify = now;
      _pendingProgressNotify?.cancel();
      _pendingProgressNotify = null;
      notifyListeners();
      return;
    }

    // Make sure the final position of a burst is not dropped.
    _pendingProgressNotify ??= Timer(_progressNotifyInterval - elapsed, () {
      _pendingProgressNotify = null;
      _lastProgressNotify = DateTime.now();
      notifyListeners();
    });
  }

  Future<void> _loadHistory() async {
    final loaded = await _storageService.loadHistory();
    for (final task in loaded) {
      // fromJson already demotes interrupted downloads to `failed`; give them a
      // message so the UI explains why they need a retry.
      if (task.status == DownloadStatus.failed && task.errorMessage == null) {
        task.errorMessage = 'Tải bị gián đoạn khi ứng dụng đóng. Hãy thử lại.';
      }
    }
    _tasks
      ..clear()
      ..addAll(loaded);
    notifyListeners();
  }

  Future<void> _saveHistory() => _storageService.saveHistory(_tasks);

  Future<DownloadTask> startNewDownload({
    required VideoMetadata metadata,
    required VideoQualityOption quality,
    bool autoSaveToGallery = true,
  }) async {
    // Do not let the asynchronous history restore clear a task that the user
    // starts immediately after launch.
    await _historyReady;

    final task = DownloadTask(
      id: _uuid.v4(),
      videoId: metadata.id,
      title: metadata.title,
      author: metadata.author,
      thumbnailUrl: metadata.coverUrl,
      downloadUrl: quality.downloadUrl,
      originalUrl: metadata.originalUrl,
      platform: metadata.platform,
      qualityLabel: quality.label,
      format: quality.format,
      isAudioOnly: quality.isAudioOnly,
      headers: quality.headers,
      totalBytes: quality.sizeBytes ?? 0,
    );

    _tasks.insert(0, task);
    notifyListeners();
    await _saveHistory();

    unawaited(_executeDownload(task, autoSaveToGallery: autoSaveToGallery));
    return task;
  }

  Future<void> _executeDownload(
    DownloadTask task, {
    bool autoSaveToGallery = true,
  }) async {
    await _downloadService.startDownload(
      task: task,
      autoSaveToGallery: autoSaveToGallery,
      onProgress: (_, _, _, _, _) => _notifyProgress(),
      onComplete: (_, _) {
        notifyListeners();
        _saveHistory();
      },
      onError: (_, _) {
        notifyListeners();
        _saveHistory();
      },
    );
    // Covers the pause / cancel paths, which finish without a callback.
    notifyListeners();
    await _saveHistory();
  }

  void cancelTask(String taskId) {
    _downloadService.cancelDownload(taskId);
    final task = _findTask(taskId);
    if (task == null) return;
    task.status = DownloadStatus.cancelled;
    task.downloadSpeed = 0.0;
    notifyListeners();
    _saveHistory();
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
    bool autoSaveToGallery = true,
  }) async {
    if (task.status != DownloadStatus.paused) return;
    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    notifyListeners();
    await _executeDownload(task, autoSaveToGallery: autoSaveToGallery);
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

    final refreshedUrl = await _refreshDownloadUrl(task);
    if (refreshedUrl != null) {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      final refreshed = task.withRefreshedSource(
        downloadUrl: refreshedUrl.downloadUrl,
        headers: refreshedUrl.headers,
      );
      if (index != -1) _tasks[index] = refreshed;
      notifyListeners();
      await _executeDownload(refreshed, autoSaveToGallery: autoSaveToGallery);
      return;
    }

    await _executeDownload(task, autoSaveToGallery: autoSaveToGallery);
  }

  /// Re-extracts [task]'s source link and returns the option matching the
  /// quality originally chosen, or null when re-extraction is not possible.
  Future<VideoQualityOption?> _refreshDownloadUrl(DownloadTask task) async {
    if (task.originalUrl.isEmpty) return null;
    try {
      final metadata = await ExtractorRegistry.extract(task.originalUrl);
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
    if (task.isActive || task.status == DownloadStatus.paused) {
      _downloadService.cancelDownload(taskId);
    }
    if (deleteLocalFile && task.filePath != null) {
      await PlatformFileHelper.deleteFile(task.filePath!);
    }
    _tasks.removeAt(index);
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
    notifyListeners();
    await _saveHistory();
  }

  Future<bool> saveToGalleryManually(DownloadTask task) async {
    if (task.filePath == null) return false;
    final success = await _storageService.saveToGallery(
      task.filePath!,
      isAudio: task.isAudioOnly,
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

  Future<void> shareFile(DownloadTask task) async {
    if (task.filePath == null) return;
    await _downloadService.shareFile(
      task.filePath!,
      text: 'Tải bằng NimbleClip: ${task.title}',
    );
  }

  DownloadTask? _findTask(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}
