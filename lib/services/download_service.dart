import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/cors_helper.dart';
import '../core/utils/media_file_validator.dart';
import '../core/utils/platform_file.dart';
import '../core/utils/web_download_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task.dart';
import '../models/video_metadata.dart' show MediaKind;
import 'storage_service.dart';

typedef DownloadProgressCallback =
    void Function(
      DownloadTask task,
      double progress,
      int receivedBytes,
      int totalBytes,
      double speedBytesPerSec,
    );

abstract interface class DownloadGateway {
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  });

  void cancelDownload(String taskId);
  bool pauseDownload(String taskId);
  bool isRunning(String taskId);
  Future<FileActionResult> openFile(String filePath);
  Future<FileActionResult> shareFile(String filePath, {String? text});
}

class DownloadService implements DownloadGateway {
  DownloadService({
    Dio? dio,
    StorageService? storageService,
    this.validator = const MediaFileValidator(),
  }) : _dio = dio ?? _createDio(),
       _storage = storageService ?? StorageService();

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers: {'User-Agent': AppConstants.defaultUserAgent, 'Accept': '*/*'},
    ),
  );

  final Dio _dio;
  final StorageService _storage;
  final MediaFileValidator validator;

  final Map<String, CancelToken> _cancelTokens = {};
  // Task ids cancelled by a pause rather than by the user abandoning the
  // download — their partial file is kept so a resume can append to it.
  final Set<String> _pausedTaskIds = {};

  static const String _pauseReason = 'paused-by-user';

  /// Uses a short UUID-style name so Gallery apps receive a predictable,
  /// filesystem-safe display name regardless of the post caption.
  String buildFileName(DownloadTask task, {String? extension}) {
    final compactId = task.id.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final base = compactId.isEmpty
        ? 'NimbleClip'
        : compactId.substring(0, compactId.length.clamp(0, 12));
    final ext = (extension ?? task.format).replaceAll('.', '').trim();
    final safeExtension = ext.isEmpty ? 'mp4' : ext;
    return '$base.$safeExtension';
  }

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    final fileName = buildFileName(task);

    if (kIsWeb) {
      return _startWebDownload(task, fileName, onProgress, onComplete, onError);
    }

    final downloadDirPath = await _storage.getDownloadDirectory();
    final savePath = downloadDirPath != null
        ? '$downloadDirPath/$fileName'
        : fileName;

    task.filePath = savePath;
    task.status = DownloadStatus.downloading;
    task.errorMessage = null;

    // Resume from a partial file left by a pause, but only if the server
    // honours byte ranges — appending to a partial file when the server replies
    // with a fresh 200 would splice two copies together.
    var existingBytes = await PlatformFileHelper.fileSize(savePath);
    if (existingBytes > 0 &&
        !await _supportsRangeRequests(task, existingBytes)) {
      await PlatformFileHelper.deleteFile(savePath);
      existingBytes = 0;
    }

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;
    _pausedTaskIds.remove(task.id);

    var lastBytes = existingBytes;
    var lastTime = DateTime.now();
    var currentSpeed = 0.0;
    var currentSavePath = savePath;

    try {
      final response = await _dio.download(
        task.downloadUrl,
        savePath,
        cancelToken: cancelToken,
        deleteOnError: false,
        fileAccessMode: existingBytes > 0
            ? FileAccessMode.append
            : FileAccessMode.write,
        options: Options(
          headers: {
            ...?task.headers,
            if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
          },
          followRedirects: true,
          // A resumed transfer must be a real partial response. Accepting a
          // fresh 200 here while appending would silently corrupt the file.
          validateStatus: (status) =>
              status != null &&
              (existingBytes > 0 ? status == 206 : status < 400),
        ),
        onReceiveProgress: (received, total) {
          // With a Range request these counters describe the remaining slice,
          // so shift them back onto the whole-file scale.
          final absoluteReceived = existingBytes + received;
          final absoluteTotal = total > 0 ? existingBytes + total : 0;

          task.receivedBytes = absoluteReceived;
          task.totalBytes = absoluteTotal;
          task.progress = absoluteTotal > 0
              ? absoluteReceived / absoluteTotal
              : 0.0;

          final now = DateTime.now();
          final msPassed = now.difference(lastTime).inMilliseconds;
          if (msPassed >= 500) {
            currentSpeed = (absoluteReceived - lastBytes) / (msPassed / 1000.0);
            lastBytes = absoluteReceived;
            lastTime = now;
          }
          task.downloadSpeed = currentSpeed;

          onProgress(
            task,
            task.progress,
            absoluteReceived,
            absoluteTotal,
            currentSpeed,
          );
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
        return await startDownload(
          task: task,
          l10n: l10n,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          autoSaveToGallery: autoSaveToGallery,
        );
      }

      _cancelTokens.remove(task.id);
      final contentType = response.headers.value('content-type');
      final actualExtension = await _validateDownloadedMedia(
        task,
        savePath,
        contentType,
        l10n,
      );
      var completedPath = savePath;
      if (actualExtension.toLowerCase() != task.format.toLowerCase()) {
        final correctedName = buildFileName(task, extension: actualExtension);
        final separator = savePath.lastIndexOf(RegExp(r'[/\\]'));
        final correctedPath = separator == -1
            ? correctedName
            : '${savePath.substring(0, separator + 1)}$correctedName';
        completedPath = await PlatformFileHelper.renameFile(
          savePath,
          correctedPath,
        );
        currentSavePath = completedPath;
      }
      task.filePath = completedPath;
      task.format = actualExtension;
      if (task.kind == MediaKind.video &&
          !await PlatformFileHelper.isPlayableVideo(completedPath)) {
        throw FormatException(l10n.invalidDownloadedMedia);
      }
      task.status = DownloadStatus.completed;
      task.progress = 1.0;
      task.downloadSpeed = 0.0;
      task.completedAt = DateTime.now();
      if (task.totalBytes == 0) {
        task.totalBytes = await PlatformFileHelper.fileSize(completedPath);
        task.receivedBytes = task.totalBytes;
      }

      if (autoSaveToGallery && !task.isAudioOnly) {
        task.isSavedToGallery = await _storage.saveToGallery(
          completedPath,
          isImage: task.isImage,
        );
      }

      onComplete(task, completedPath);
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
          l10n: l10n,
          onProgress: onProgress,
          onComplete: onComplete,
          onError: onError,
          autoSaveToGallery: autoSaveToGallery,
        );
      }

      task.status = DownloadStatus.failed;
      task.errorMessage = _describe(e, l10n);
      await PlatformFileHelper.deleteFile(currentSavePath);
      onError(task, task.errorMessage!);
    } catch (e) {
      _cancelTokens.remove(task.id);
      task.downloadSpeed = 0.0;
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      await PlatformFileHelper.deleteFile(currentSavePath);
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
      final supported =
          response.statusCode == 206 &&
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
    final match = RegExp(
      r'^bytes\s+(\d+)-',
      caseSensitive: false,
    ).firstMatch(value.trim());
    return match != null && int.tryParse(match.group(1)!) == offset;
  }

  Future<String> _validateDownloadedMedia(
    DownloadTask task,
    String filePath,
    String? contentType,
    AppLocalizations l10n,
  ) async {
    final normalizedType = contentType?.split(';').first.trim().toLowerCase();
    if (normalizedType != null &&
        (normalizedType.startsWith('text/') ||
            normalizedType == 'application/json' ||
            normalizedType == 'application/xml')) {
      throw FormatException(l10n.invalidDownloadedMedia);
    }

    final header = await PlatformFileHelper.readFileHeader(
      filePath,
      length: 512,
    );
    final inspection = validator.inspect(header);
    if (inspection == null ||
        !validator.matchesExpectedKind(inspection, task.kind)) {
      throw FormatException(l10n.invalidDownloadedMedia);
    }

    final expectedPrefix = task.isImage
        ? 'image/'
        : task.isAudioOnly
        ? 'audio/'
        : 'video/';
    if (normalizedType != null &&
        normalizedType.isNotEmpty &&
        normalizedType != 'application/octet-stream' &&
        normalizedType != 'binary/octet-stream' &&
        normalizedType != 'application/force-download' &&
        !normalizedType.startsWith(expectedPrefix)) {
      throw FormatException(l10n.invalidDownloadedMedia);
    }
    return validator.extensionFor(inspection, task.kind);
  }

  /// Stops a download and discards its partial file.
  @override
  void cancelDownload(String taskId) {
    _pausedTaskIds.remove(taskId);
    _cancelTokens.remove(taskId)?.cancel('User cancelled download');
  }

  /// Stops a download but keeps the partial file so it can be resumed.
  /// Returns false when the task was not running.
  @override
  bool pauseDownload(String taskId) {
    final token = _cancelTokens.remove(taskId);
    if (token == null) return false;
    _pausedTaskIds.add(taskId);
    token.cancel(_pauseReason);
    return true;
  }

  @override
  bool isRunning(String taskId) => _cancelTokens.containsKey(taskId);

  String _describe(DioException e, AppLocalizations l10n) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return l10n.networkTimeout;
      case DioExceptionType.connectionError:
        return l10n.serverConnectionFailed;
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403 || code == 401) {
          return l10n.downloadLinkExpired(code!);
        }
        return l10n.serverError(code?.toString() ?? 'unknown');
      default:
        return e.message ?? l10n.unknownNetworkError;
    }
  }

  @override
  Future<FileActionResult> openFile(String filePath) =>
      PlatformFileHelper.openFile(filePath);

  @override
  Future<FileActionResult> shareFile(String filePath, {String? text}) =>
      PlatformFileHelper.shareFile(filePath, text: text);
}
