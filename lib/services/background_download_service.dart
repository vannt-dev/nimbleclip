import 'dart:async';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;

import '../core/constants/app_constants.dart';
import '../core/utils/media_file_validator.dart';
import '../core/utils/platform_file.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task.dart';
import 'download_service.dart';
import 'storage_service.dart';

DownloadGateway createDefaultDownloadService() {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    return BackgroundDownloadService();
  }
  return DownloadService();
}

/// Mobile download gateway backed by Android DownloadWorker and iOS
/// URLSession. Transfers therefore keep running while Flutter is suspended.
class BackgroundDownloadService
    implements DownloadGateway, RecoverableDownloadGateway {
  BackgroundDownloadService({
    StorageService? storageService,
    this.validator = const MediaFileValidator(),
    this.requestNotificationPermission = true,
  }) : _storage = storageService ?? StorageService() {
    _updates = bg.FileDownloader().updates.listen(_onUpdate);
    bg.FileDownloader().configureNotificationForGroup(
      bg.FileDownloader.defaultGroup,
      running: const bg.TaskNotification(
        'NimbleClip - {displayName}',
        '{progress} | {networkSpeed} | {timeRemaining}',
      ),
      complete: const bg.TaskNotification(
        'NimbleClip - {displayName}',
        'Download complete',
      ),
      error: const bg.TaskNotification(
        'NimbleClip - {displayName}',
        'Download failed',
      ),
      paused: const bg.TaskNotification(
        'NimbleClip - {displayName}',
        'Download paused',
      ),
      progressBar: true,
      tapOpensFile: true,
    );
  }

  final StorageService _storage;
  final MediaFileValidator validator;
  final bool requestNotificationPermission;
  late final StreamSubscription<bg.TaskUpdate> _updates;
  final Map<String, bg.DownloadTask> _nativeTasks = {};
  final Map<String, _BackgroundContext> _contexts = {};
  final Set<String> _running = {};
  final Set<String> _finishing = {};
  Future<void>? _startFuture;

  Future<void> _ensureStarted() =>
      _startFuture ??= bg.FileDownloader().start(autoCleanDatabase: true);

  @override
  Future<void> recoverDownloads({
    required Iterable<DownloadTask> tasks,
    required void Function(DownloadTask task) onChanged,
    required void Function(DownloadTask task) onTerminal,
  }) async {
    await bg.FileDownloader().ready;
    final records = await bg.FileDownloader().database.allRecords();
    final recordsById = {for (final record in records) record.taskId: record};

    for (final task in tasks) {
      final record = recordsById[task.id];
      final nativeTask = record?.task;
      if (record == null || nativeTask is! bg.DownloadTask) continue;
      _nativeTasks[task.id] = nativeTask;
      task
        ..filePath = await nativeTask.filePath()
        ..progress = record.progress.clamp(0.0, 1.0)
        ..totalBytes = record.expectedFileSize > 0
            ? record.expectedFileSize
            : task.totalBytes
        ..receivedBytes = record.expectedFileSize > 0
            ? (record.expectedFileSize * task.progress).round()
            : task.receivedBytes
        ..errorMessage = null;

      if (record.status == bg.TaskStatus.paused) {
        task.status = DownloadStatus.paused;
        onChanged(task);
        continue;
      }
      if (record.status == bg.TaskStatus.failed ||
          record.status == bg.TaskStatus.notFound ||
          record.status == bg.TaskStatus.canceled) {
        continue;
      }

      _contexts[task.id] = _BackgroundContext(
        task: task,
        l10n: lookupAppLocalizations(const Locale('en')),
        onProgress: (changed, _, _, _, _) {
          changed.notifyProgressChanged();
          onChanged(changed);
        },
        onComplete: (changed, _) => onTerminal(changed),
        onError: (changed, _) => onTerminal(changed),
        autoSaveToGallery: false,
        completer: Completer<void>(),
      );
      task.status = record.status == bg.TaskStatus.complete
          ? DownloadStatus.downloading
          : record.status == bg.TaskStatus.enqueued
          ? DownloadStatus.queued
          : DownloadStatus.downloading;
      if (task.status == DownloadStatus.downloading) _running.add(task.id);
      onChanged(task);
    }

    // Contexts must be registered before start(), because it immediately
    // replays status updates collected while Flutter was not running.
    await _ensureStarted();

    for (final task in tasks) {
      final record = recordsById[task.id];
      if (record?.status == bg.TaskStatus.complete &&
          _contexts.containsKey(task.id) &&
          _finishing.add(task.id)) {
        await _complete(
          task.id,
          bg.TaskStatusUpdate(record!.task, bg.TaskStatus.complete),
        );
      }
    }
  }

  String buildFileName(DownloadTask task, {String? extension}) {
    final compactId = task.id.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final length = compactId.length.clamp(0, 12);
    final idPart = compactId.isEmpty
        ? 'NimbleClip'
        : compactId.substring(0, length);
    final platformPrefix = task.platform.name == 'twitter'
        ? 'x'
        : task.platform.name;
    final ext = (extension ?? task.format).replaceAll('.', '').trim();
    return '${platformPrefix}_$idPart.${ext.isEmpty ? 'mp4' : ext}';
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
    await _ensureStarted();
    final completer = Completer<void>();
    _contexts[task.id] = _BackgroundContext(
      task: task,
      l10n: l10n,
      onProgress: onProgress,
      onComplete: onComplete,
      onError: onError,
      autoSaveToGallery: autoSaveToGallery,
      completer: completer,
    );

    try {
      final existing = _nativeTasks[task.id];
      // DownloadProvider changes paused -> queued before handing the task back
      // to the worker, so the retained native task is the reliable resume flag.
      if (existing != null) {
        final resumed = await bg.FileDownloader().resume(existing);
        if (!resumed) {
          _nativeTasks.remove(task.id);
          await _enqueue(task, l10n);
        }
      } else {
        await _enqueue(task, l10n);
      }
    } catch (error) {
      _fail(task.id, error.toString());
    }
    await completer.future;
  }

  Future<void> _enqueue(DownloadTask task, AppLocalizations l10n) async {
    try {
      final status = await bg.FileDownloader().permissions.status(
        bg.PermissionType.notifications,
      );
      if (requestNotificationPermission &&
          status != bg.PermissionStatus.granted) {
        await bg.FileDownloader().permissions.request(
          bg.PermissionType.notifications,
        );
      }
    } catch (_) {
      // Notification permission is optional; the transfer itself can proceed.
    }
    final directory = await _storage.getDownloadDirectory();
    if (directory == null) {
      throw StateError(l10n.unknownNetworkError);
    }
    final nativeTask = bg.DownloadTask(
      taskId: task.id,
      url: task.downloadUrl,
      filename: buildFileName(task),
      directory: directory,
      baseDirectory: bg.BaseDirectory.root,
      headers: {
        'User-Agent': AppConstants.defaultUserAgent,
        'Accept': '*/*',
        ...?task.headers,
      },
      updates: bg.Updates.statusAndProgress,
      retries: 2,
      allowPause: true,
      displayName: task.title,
      metaData: task.originalUrl,
    );
    _nativeTasks[task.id] = nativeTask;
    task
      ..status = DownloadStatus.queued
      ..filePath = await nativeTask.filePath()
      ..errorMessage = null;
    if (!await bg.FileDownloader().enqueue(nativeTask)) {
      _fail(task.id, l10n.unknownNetworkError);
    }
  }

  void _onUpdate(bg.TaskUpdate update) {
    final id = update.task.taskId;
    final context = _contexts[id];
    if (context == null) return;
    final task = context.task;

    if (update is bg.TaskProgressUpdate && update.progress >= 0) {
      final total = update.hasExpectedFileSize ? update.expectedFileSize : 0;
      final received = total > 0 ? (total * update.progress).round() : 0;
      final speed = update.hasNetworkSpeed
          ? update.networkSpeed * 1024 * 1024
          : 0.0;
      task
        ..status = DownloadStatus.downloading
        ..progress = update.progress.clamp(0.0, 1.0)
        ..totalBytes = total
        ..receivedBytes = received
        ..downloadSpeed = speed;
      _running.add(id);
      context.onProgress(task, task.progress, received, total, speed);
      return;
    }

    if (update is! bg.TaskStatusUpdate) return;
    switch (update.status) {
      case bg.TaskStatus.enqueued:
        task.status = DownloadStatus.queued;
      case bg.TaskStatus.running:
      case bg.TaskStatus.waitingToRetry:
        task.status = DownloadStatus.downloading;
        _running.add(id);
      case bg.TaskStatus.paused:
        _running.remove(id);
        task
          ..status = DownloadStatus.paused
          ..downloadSpeed = 0;
        _finishAwait(id, keepNativeTask: true);
      case bg.TaskStatus.complete:
        if (_finishing.add(id)) unawaited(_complete(id, update));
      case bg.TaskStatus.canceled:
        _running.remove(id);
        task
          ..status = DownloadStatus.cancelled
          ..downloadSpeed = 0;
        _finishAwait(id);
      case bg.TaskStatus.failed:
      case bg.TaskStatus.notFound:
        _fail(
          id,
          update.exception?.description ??
              'Download failed (${update.responseStatusCode ?? 'unknown'})',
        );
    }
  }

  Future<void> _complete(String id, bg.TaskStatusUpdate update) async {
    final context = _contexts[id];
    final nativeTask = _nativeTasks[id];
    if (context == null || nativeTask == null) return;
    final task = context.task;
    var path = await nativeTask.filePath();
    try {
      final header = await PlatformFileHelper.readFileHeader(path, length: 512);
      final inspection = validator.inspect(header);
      if (inspection == null ||
          !validator.matchesExpectedKind(inspection, task.kind)) {
        throw FormatException(context.l10n.invalidDownloadedMedia);
      }
      final extension = validator.extensionFor(inspection, task.kind);
      if (extension.toLowerCase() != task.format.toLowerCase()) {
        final slash = path.lastIndexOf(RegExp(r'[/\\]'));
        final corrected = slash < 0
            ? buildFileName(task, extension: extension)
            : '${path.substring(0, slash + 1)}${buildFileName(task, extension: extension)}';
        path = await PlatformFileHelper.renameFile(path, corrected);
      }
      task
        ..filePath = path
        ..format = extension
        ..status = DownloadStatus.completed
        ..progress = 1
        ..receivedBytes = await PlatformFileHelper.fileSize(path)
        ..downloadSpeed = 0
        ..completedAt = DateTime.now();
      task.totalBytes = task.receivedBytes;
      if (context.autoSaveToGallery && !task.isAudioOnly) {
        task.isSavedToGallery = await _storage.saveToGallery(
          path,
          isImage: task.isImage,
        );
      }
      context.onComplete(task, path);
      _finishAwait(id);
    } catch (error) {
      await PlatformFileHelper.deleteFile(path);
      _fail(id, error.toString());
    } finally {
      _finishing.remove(id);
    }
  }

  void _fail(String id, String message) {
    final context = _contexts[id];
    if (context == null) return;
    _running.remove(id);
    context.task
      ..status = DownloadStatus.failed
      ..errorMessage = message
      ..downloadSpeed = 0;
    context.onError(context.task, message);
    _finishAwait(id);
  }

  void _finishAwait(String id, {bool keepNativeTask = false}) {
    _running.remove(id);
    final context = _contexts.remove(id);
    if (!keepNativeTask) _nativeTasks.remove(id);
    if (context != null && !context.completer.isCompleted) {
      context.completer.complete();
    }
  }

  @override
  void cancelDownload(String taskId) {
    unawaited(bg.FileDownloader().cancelTaskWithId(taskId));
  }

  @override
  bool pauseDownload(String taskId) {
    final task = _nativeTasks[taskId];
    if (task == null || !_running.contains(taskId)) return false;
    unawaited(bg.FileDownloader().pause(task));
    return true;
  }

  @override
  bool isRunning(String taskId) => _running.contains(taskId);

  @override
  void dispose() {
    unawaited(_updates.cancel());
  }
}

class _BackgroundContext {
  const _BackgroundContext({
    required this.task,
    required this.l10n,
    required this.onProgress,
    required this.onComplete,
    required this.onError,
    required this.autoSaveToGallery,
    required this.completer,
  });

  final DownloadTask task;
  final AppLocalizations l10n;
  final DownloadProgressCallback onProgress;
  final void Function(DownloadTask task, String filePath) onComplete;
  final void Function(DownloadTask task, String error) onError;
  final bool autoSaveToGallery;
  final Completer<void> completer;
}
