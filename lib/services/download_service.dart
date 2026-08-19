import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/cors_helper.dart';
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
  // Task ids cancelled by a pause rather than by the user abandoning the
  // download — their partial file is kept so a resume can append to it.
  final Set<String> _pausedTaskIds = {};

  static const String _pauseReason = 'paused-by-user';

  /// Builds a filesystem-safe name. Windows reserves `\/:*?"<>|`, and a name
  /// that is only punctuation collapses to empty, so a fallback is applied.
  String buildFileName(DownloadTask task) {
    final sanitized = task.title
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        // A title made entirely of reserved characters collapses to a run of
        // underscores, which is a legal but meaningless file name.
        .replaceAll(RegExp(r'^[_\s.]+|[_\s.]+$'), '')
        .trim();

    // Leave room for the suffix and extension within the common 255-byte limit.
    var base = sanitized.isEmpty ? 'SnapVideo' : sanitized;
    if (base.length > 120) base = base.substring(0, 120).trim();

    final suffix = task.id.length >= 6 ? task.id.substring(0, 6) : task.id;
    final ext = task.format.replaceAll('.', '').trim();
    final extension = ext.isEmpty ? 'mp4' : ext;

    return suffix.isEmpty
        ? '$base.$extension'
        : '${base}_$suffix.$extension';
  }

  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    bool autoSaveToGallery = true,
  }) async {
    final fileName = buildFileName(task);

    if (kIsWeb) {
      return _startWebDownload(task, fileName, onProgress, onComplete, onError);
    }

    final storage = StorageService();
    final downloadDirPath = await storage.getDownloadDirectory();
    final savePath =
        downloadDirPath != null ? '$downloadDirPath/$fileName' : fileName;

    task.filePath = savePath;
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;

    // Resume from a partial file left by a pause, but only if the server
    // honours byte ranges — appending to a partial file when the server replies
    // with a fresh 200 would splice two copies together.
    var existingBytes = await PlatformFileHelper.fileSize(savePath);
    if (existingBytes > 0 && !await _supportsRangeRequests(task, existingBytes)) {
      await PlatformFileHelper.deleteFile(savePath);
      existingBytes = 0;
    }

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    _pausedTaskIds.remove(task.id);

    var lastBytes = existingBytes;
    var lastTime = DateTime.now();
    var currentSpeed = 0.0;

    try {
      final response = await _dio.download(
        task.downloadUrl,
        savePath,
        cancelToken: cancelToken,
        deleteOnError: false,
        fileAccessMode:
            existingBytes > 0 ? FileAccessMode.append : FileAccessMode.write,
        options: Options(
          headers: {
            ...?task.headers,
            if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
          },
          followRedirects: true,
          // A resumed transfer must be a real partial response. Accepting a
          // fresh 200 here while appending would silently corrupt the file.
          validateStatus: (status) => status != null &&
              (existingBytes > 0 ? status == 206 : status < 400),
        ),
        onReceiveProgress: (received, total) {
          // With a Range request these counters describe the remaining slice,
          // so shift them back onto the whole-file scale.
          final absoluteReceived = existingBytes + received;
          final absoluteTotal = total > 0 ? existingBytes + total : 0;

          task.receivedBytes = absoluteReceived;
          task.totalBytes = absoluteTotal;
          task.progress =
              absoluteTotal > 0 ? absoluteReceived / absoluteTotal : 0.0;

          final now = DateTime.now();
          final msPassed = now.difference(lastTime).inMilliseconds;
          if (msPassed >= 500) {
            currentSpeed =
                (absoluteReceived - lastBytes) / (msPassed / 1000.0);
            lastBytes = absoluteReceived;
            lastTime = now;
          }
          task.downloadSpeed = currentSpeed;

          onProgress(task, task.progress, absoluteReceived, absoluteTotal,
              currentSpeed);
        },
      );

      if (existingBytes > 0 &&
          !_contentRangeStartsAt(
            response.headers.value('content-range'),
            existingBytes,
          )) {
        _cancelTokens.remove(task.id);
        await PlatformFileHelper.deleteFile(savePath);
        task
          ..progress = 0
          ..receivedBytes = 0
          ..totalBytes = 0;
        return startDownload(
          task: task,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          autoSaveToGallery: autoSaveToGallery,
        );
      }

      _cancelTokens.remove(task.id);
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.downloadSpeed = 0.0;
      task.completedAt = DateTime.now();
      if (task.totalBytes == 0) {
        task.totalBytes = await PlatformFileHelper.fileSize(savePath);
        task.receivedBytes = task.totalBytes;
      }

      if (autoSaveToGallery && !task.isAudioOnly) {
        task.isSavedToGallery = await storage.saveToGallery(savePath);
      }

      onComplete(task, savePath);
    } on DioException catch (e) {
      _cancelTokens.remove(task.id);
      task.downloadSpeed = 0.0;

      if (CancelToken.isCancel(e)) {
        if (_pausedTaskIds.remove(task.id)) {
          // Partial file stays on disk for the resume.
          task.status = DownloadStatus.paused;
        } else {
          task.status = DownloadStatus.cancelled;
          await PlatformFileHelper.deleteFile(savePath);
        }
        return;
      }

      // The range probe succeeded but the real transfer changed its mind and
      // returned a full response. Discard the partial bytes and retry once from
      // zero; the recursive call cannot loop because the file is now absent.
      if (existingBytes > 0 &&
          e.type == DioExceptionType.badResponse &&
          e.response?.statusCode == 200) {
        await PlatformFileHelper.deleteFile(savePath);
        task
          ..progress = 0
          ..receivedBytes = 0
          ..totalBytes = 0;
        return startDownload(
          task: task,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          autoSaveToGallery: autoSaveToGallery,
        );
      }

      task.status = DownloadStatus.failed;
      task.errorMessage = _describe(e);
      await PlatformFileHelper.deleteFile(savePath);
      onError(task, task.errorMessage!);
    } catch (e) {
      _cancelTokens.remove(task.id);
      task.downloadSpeed = 0.0;
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      await PlatformFileHelper.deleteFile(savePath);
      onError(task, task.errorMessage!);
    }
  }

  /// In a browser the file is handed to the download manager rather than
  /// written by the app, so there is no byte-level progress to report.
  ///
  /// The URL is routed through the local proxy with a filename: the `download`
  /// attribute on an anchor is ignored for cross-origin URLs, so without a
  /// same-origin response carrying `Content-Disposition: attachment` the browser
  /// would navigate to the video instead of saving it.
  void _startWebDownload(
    DownloadTask task,
    String fileName,
    DownloadProgressCallback onProgress,
    void Function(DownloadTask task, String filePath) onComplete,
    void Function(DownloadTask task, String error) onError,
  ) {
    task.status = DownloadStatus.downloading;
    task.progress = 0.0;
    onProgress(task, 0.0, 0, 0, 0);

    try {
      triggerWebDownload(
        CorsHelper.wrap(task.downloadUrl, downloadFileName: fileName),
        fileName,
      );

      // Browsers do not expose completion or cancellation of a download that
      // was handed to their download manager. Record that hand-off honestly
      // instead of claiming a local file exists.
      task.status = DownloadStatus.handedOff;
      task.progress = 0.0;
      task.downloadSpeed = 0.0;
      task.filePath = null;
      task.completedAt = DateTime.now();
      onComplete(task, '');
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      onError(task, task.errorMessage!);
    }
  }

  /// Probes whether the source will serve a byte range starting at [offset].
  Future<bool> _supportsRangeRequests(DownloadTask task, int offset) async {
    try {
      // A HEAD response advertising Accept-Ranges is only a hint. Probe one
      // actual byte and require both 206 and a matching Content-Range.
      final response = await _dio.get<ResponseBody>(
        task.downloadUrl,
        options: Options(
          headers: {...?task.headers, 'Range': 'bytes=$offset-$offset'},
          followRedirects: true,
          responseType: ResponseType.stream,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final supported = response.statusCode == 206 &&
          _contentRangeStartsAt(
            response.headers.value('content-range'),
            offset,
          );
      final stream = response.data?.stream;
      if (stream != null) {
        final subscription = stream.listen((_) {});
        await subscription.cancel();
      }
      return supported;
    } catch (_) {
      return false;
    }
  }

  bool _contentRangeStartsAt(String? value, int offset) {
    if (value == null) return false;
    final match = RegExp(r'^bytes\s+(\d+)-', caseSensitive: false)
        .firstMatch(value.trim());
    return match != null && int.tryParse(match.group(1)!) == offset;
  }

  /// Stops a download and discards its partial file.
  void cancelDownload(String taskId) {
    _pausedTaskIds.remove(taskId);
    _cancelTokens.remove(taskId)?.cancel('User cancelled download');
  }

  /// Stops a download but keeps the partial file so it can be resumed.
  /// Returns false when the task was not running.
  bool pauseDownload(String taskId) {
    final token = _cancelTokens.remove(taskId);
    if (token == null) return false;
    _pausedTaskIds.add(taskId);
    token.cancel(_pauseReason);
    return true;
  }

  bool isRunning(String taskId) => _cancelTokens.containsKey(taskId);

  String _describe(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Hết thời gian chờ mạng. Kiểm tra kết nối rồi thử lại.';
      case DioExceptionType.connectionError:
        return 'Không kết nối được tới máy chủ.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403 || code == 401) {
          return 'Liên kết tải đã hết hạn ($code). Hãy phân tích lại video.';
        }
        return 'Máy chủ trả về lỗi $code.';
      default:
        return e.message ?? 'Lỗi mạng không xác định.';
    }
  }

  Future<void> openFile(String filePath) =>
      PlatformFileHelper.openFile(filePath);

  Future<void> shareFile(String filePath, {String? text}) =>
      PlatformFileHelper.shareFile(filePath, text: text);
}
