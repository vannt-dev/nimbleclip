import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/platform_file.dart';
import '../core/utils/web_download_helper.dart';
import '../models/download_task.dart';
import 'storage_service.dart';

typedef DownloadProgressCallback = void Function(
  DownloadTask task,
  double progress,
  int receivedBytes,
  int totalBytes,
  double speedBytesPerSec,
);

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {
        'User-Agent': AppConstants.defaultUserAgent,
        'Accept': '*/*',
      },
    ),
  );

  final Map<String, CancelToken> _cancelTokens = {};

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// Starts downloading a task
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required Function(DownloadTask task, String filePath) onComplete,
    required Function(DownloadTask task, String error) onError,
    bool autoSaveToGallery = true,
  }) async {
    final safeTitle = _sanitizeFileName(task.title);
    final ext = task.format.replaceAll('.', '');
    final fileName = '${safeTitle}_${task.id.substring(0, 6)}.$ext';

    // 1. Web Browser Handling
    if (kIsWeb) {
      task.status = DownloadStatus.downloading;
      task.progress = 0.5;
      onProgress(task, 0.5, 0, 0, 0);

      try {
        // Trigger browser native file download
        triggerWebDownload(task.downloadUrl, fileName);

        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.downloadSpeed = 0.0;
        task.filePath = fileName;
        task.completedAt = DateTime.now();

        onComplete(task, fileName);
      } catch (e) {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();
        onError(task, task.errorMessage!);
      }
      return;
    }

    // 2. Native Mobile & Desktop Handling (Android, iOS, Windows, macOS, Linux)
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    task.status = DownloadStatus.downloading;
    task.errorMessage = null;

    final storage = StorageService();
    final downloadDirPath = await storage.getDownloadDirectory();

    final savePath = downloadDirPath != null ? '$downloadDirPath/$fileName' : fileName;
    task.filePath = savePath;

    int lastBytes = 0;
    DateTime lastTime = DateTime.now();
    double currentSpeed = 0.0;

    try {
      final response = await _dio.download(
        task.downloadUrl,
        savePath,
        cancelToken: cancelToken,
        options: Options(
          headers: task.headers,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            task.totalBytes = total;
            task.receivedBytes = received;
            task.progress = received / total;

            final now = DateTime.now();
            final msPassed = now.difference(lastTime).inMilliseconds;
            if (msPassed >= 500) {
              final bytesDelta = received - lastBytes;
              currentSpeed = (bytesDelta / (msPassed / 1000.0));
              lastBytes = received;
              lastTime = now;
            }
            task.downloadSpeed = currentSpeed;

            onProgress(task, task.progress, received, total, currentSpeed);
          }
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        task.status = DownloadStatus.completed;
        task.progress = 1.0;
        task.downloadSpeed = 0.0;
        task.completedAt = DateTime.now();

        if (autoSaveToGallery && !task.isAudioOnly) {
          final saved = await storage.saveToGallery(savePath, isAudio: task.isAudioOnly);
          task.isSavedToGallery = saved;
        }

        _cancelTokens.remove(task.id);
        onComplete(task, savePath);
      } else {
        throw Exception('Download failed with status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.cancelled;
      } else {
        task.status = DownloadStatus.failed;
        task.errorMessage = e.message ?? 'Network error occurred';
        onError(task, task.errorMessage!);
      }
      _cancelTokens.remove(task.id);
      _cleanupFile(savePath);
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      _cancelTokens.remove(task.id);
      onError(task, task.errorMessage!);
      _cleanupFile(savePath);
    }
  }

  /// Cancels a running download
  void cancelDownload(String taskId) {
    if (_cancelTokens.containsKey(taskId)) {
      _cancelTokens[taskId]?.cancel('User cancelled download');
      _cancelTokens.remove(taskId);
    }
  }

  void _cleanupFile(String? path) {
    if (path == null || kIsWeb) return;
    PlatformFileHelper.deleteFile(path);
  }

  /// Open file using system default application
  Future<void> openFile(String filePath) async {
    await PlatformFileHelper.openFile(filePath);
  }

  /// Share file to other apps
  Future<void> shareFile(String filePath, {String? text}) async {
    await PlatformFileHelper.shareFile(filePath, text: text);
  }
}
