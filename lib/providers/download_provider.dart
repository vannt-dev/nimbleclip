import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/platform_file.dart';
import '../models/download_task.dart';
import '../models/video_metadata.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';

class DownloadProvider extends ChangeNotifier {
  final List<DownloadTask> _tasks = [];
  final DownloadService _downloadService = DownloadService();
  final StorageService _storageService = StorageService();
  final Uuid _uuid = const Uuid();

  List<DownloadTask> get allTasks => List.unmodifiable(_tasks);
  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.isActive).toList();
  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status == DownloadStatus.completed).toList();

  DownloadProvider() {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final loaded = await _storageService.loadHistory();
    _tasks.clear();
    _tasks.addAll(loaded);
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    await _storageService.saveHistory(_tasks);
  }

  Future<DownloadTask> startNewDownload({
    required VideoMetadata metadata,
    required VideoQualityOption quality,
    bool autoSaveToGallery = true,
  }) async {
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
      status: DownloadStatus.queued,
    );

    _tasks.insert(0, task);
    notifyListeners();
    await _saveHistory();

    _executeDownload(task, autoSaveToGallery: autoSaveToGallery);
    return task;
  }

  void _executeDownload(DownloadTask task, {bool autoSaveToGallery = true}) {
    _downloadService.startDownload(
      task: task,
      autoSaveToGallery: autoSaveToGallery,
      onProgress: (t, progress, received, total, speed) {
        notifyListeners();
      },
      onComplete: (t, path) {
        notifyListeners();
        _saveHistory();
      },
      onError: (t, error) {
        notifyListeners();
        _saveHistory();
      },
    );
  }

  void cancelTask(String taskId) {
    _downloadService.cancelDownload(taskId);
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      _tasks[index].status = DownloadStatus.cancelled;
      _tasks[index].downloadSpeed = 0.0;
      notifyListeners();
      _saveHistory();
    }
  }

  void retryTask(DownloadTask task, {bool autoSaveToGallery = true}) {
    task.status = DownloadStatus.queued;
    task.progress = 0.0;
    task.receivedBytes = 0;
    task.errorMessage = null;
    notifyListeners();
    _executeDownload(task, autoSaveToGallery: autoSaveToGallery);
  }

  Future<void> deleteTask(String taskId, {bool deleteLocalFile = true}) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index != -1) {
      final task = _tasks[index];
      if (task.isActive) {
        _downloadService.cancelDownload(taskId);
      }
      if (deleteLocalFile && task.filePath != null) {
        await PlatformFileHelper.deleteFile(task.filePath!);
      }
      _tasks.removeAt(index);
      notifyListeners();
      await _saveHistory();
    }
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
    if (task.filePath != null) {
      await _downloadService.openFile(task.filePath!);
    }
  }

  Future<void> shareFile(DownloadTask task) async {
    if (task.filePath != null) {
      await _downloadService.shareFile(
        task.filePath!,
        text: 'Downloaded with SnapVideo: ${task.title}',
      );
    }
  }
}
