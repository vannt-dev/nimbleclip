import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/download_file_name.dart';
import '../core/utils/media_file_validator.dart';
import '../core/utils/platform_file.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/download_task.dart';
import '../models/merge_source.dart';
import 'background_stream_pairs.dart';
import 'download_service.dart';
import 'slideshow/slideshow_failure.dart';
import 'storage_service.dart';
import 'stream_pair_gateway.dart';

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
    implements
        DownloadGateway,
        RecoverableDownloadGateway,
        StreamPairGateway,
        NetworkPolicyGateway {
  BackgroundDownloadService({
    StorageService? storageService,
    this.validator = const MediaFileValidator(),
    this.requestNotificationPermission = true,
    BackgroundStreamPairs? streamPairs,
  }) : _storage = storageService ?? StorageService(),
       _pairs = streamPairs ?? BackgroundStreamPairs(root: _streamPairRoot) {
    _updates = bg.FileDownloader().updates.listen(_onUpdate);
    // A merged video is dozens of parts; one notification counts them rather
    // than each posting its own.
    bg.FileDownloader().configureNotificationForGroup(
      streamPartGroup,
      running: const bg.TaskNotification(
        'NimbleClip',
        '{numFinished} of {numTotal} parts',
      ),
      complete: const bg.TaskNotification(
        'NimbleClip',
        'Downloaded - open NimbleClip if it does not finish',
      ),
      error: const bg.TaskNotification('NimbleClip', 'Download failed'),
      progressBar: true,
      groupNotificationId: streamPartGroup,
    );
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
  final BackgroundStreamPairs _pairs;

  /// Downloads fetched in parts rather than as one system transfer, running
  /// or paused: the ones whose task carries a part size. Everything else is a
  /// single transfer, which can also resume mid-file.
  final Map<String, SingleStreamTransfer> _partTransfers = {};
  final Set<String> _pausedParts = {};

  /// Paused downloads whose last parts arrived all the same, by where their
  /// file is: there is nothing left to resume, only to report.
  final Map<String, String> _wholeWhilePaused = {};
  Future<void>? _startFuture;

  Future<void> _ensureStarted() =>
      _startFuture ??= bg.FileDownloader().start(autoCleanDatabase: true);

  /// Where merged videos' parts wait to be joined. Not the cache: Android
  /// may clear that while parts are still arriving without the app.
  static Future<Directory> _streamPairRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/merge');

  @override
  Future<StreamPairTransfer> startStreamPair({
    required String taskId,
    required String title,
    required MergeSource source,
    required bool autoSaveToGallery,
  }) async {
    await _ensureStarted();
    await _requestNotificationPermission();
    return _pairs.startStreamPair(
      taskId: taskId,
      title: title,
      source: source,
      autoSaveToGallery: autoSaveToGallery,
    );
  }

  @override
  List<StreamPairTransfer> takeRecoveredStreamPairs() =>
      _pairs.takeRecoveredStreamPairs();

  @override
  void cancelStreamPair(String taskId) => _pairs.cancelStreamPair(taskId);

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

    // Merged videos' parts are not in `tasks` — the history holds the merged
    // task, not its parts — so they are rebuilt from their own manifests.
    await _pairs.recover();

    // Contexts must be registered before start(), because it immediately
    // replays status updates collected while Flutter was not running.
    await _ensureStarted();
    await _pairs.requeueLostParts();

    // A download in parts has no record under its own id either; what a
    // later launch needs is in its manifest, and its task says it was cut off.
    final interrupted = {for (final task in tasks) task.id: task};
    for (final transfer in _pairs.takeRecoveredSingleStreams()) {
      final task = interrupted[transfer.taskId];
      if (task == null) {
        await _discardParts(transfer);
        continue;
      }
      if (transfer.isPaused) {
        // Paused when the app was closed, and paused still: the parts that
        // arrived are kept and only a resume fetches the rest.
        task
          ..status = DownloadStatus.paused
          ..filePath = transfer.outputPath
          ..downloadSpeed = 0
          ..errorMessage = null;
        _pausedParts.add(task.id);
        _watchParts(task, transfer, running: false);
        onChanged(task);
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
      task
        ..status = DownloadStatus.downloading
        ..filePath = transfer.outputPath
        ..totalBytes = transfer.totalBytes
        ..errorMessage = null;
      _watchParts(task, transfer);
      onChanged(task);
    }

    for (final task in tasks) {
      final record = recordsById[task.id];
      if (record?.status == bg.TaskStatus.complete &&
          _contexts.containsKey(task.id) &&
          _finishing.add(task.id)) {
        await _complete(task.id, await record!.task.filePath());
      }
    }
  }

  static final RegExp _pathSeparator = RegExp(r'[/\\]');

  String buildFileName(DownloadTask task, {String? extension}) =>
      downloadFileName(task, extension: extension);

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
      if (_pausedParts.remove(task.id)) {
        // The parts that arrived before the pause are kept; the rest are
        // queued again.
        _running.add(task.id);
        task
          ..status = DownloadStatus.downloading
          ..errorMessage = null;
        final whole = _wholeWhilePaused.remove(task.id);
        if (whole != null) {
          if (_finishing.add(task.id)) await _complete(task.id, whole);
        } else if (!await _pairs.resume(task.id)) {
          _fail(task.id, l10n.unknownNetworkError);
        }
      } else if (task.partBytes case final partBytes?) {
        await _startInParts(task, partBytes, l10n);
      } else if (existing != null) {
        // DownloadProvider changes paused -> queued before handing the task
        // back to the worker, so the retained native task is the reliable
        // resume flag.
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

  Future<void> _requestNotificationPermission() async {
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
  }

  /// A running transfer is paused by the system when Wi-Fi goes away and
  /// picked up again when it returns, with the app open or not.
  @override
  Future<void> setWifiOnly(bool wifiOnly) async {
    try {
      await bg.FileDownloader().requireWiFi(
        wifiOnly ? bg.RequireWiFi.forAllTasks : bg.RequireWiFi.asSetByTask,
        rescheduleRunningTasks: true,
      );
    } catch (_) {
      // The queue still holds new downloads back; only transfers already
      // handed to the system are beyond reach.
    }
  }

  /// Queues [task]'s file in ranges of [partBytes]. When its length cannot be
  /// confirmed it is fetched as one transfer after all.
  Future<void> _startInParts(
    DownloadTask task,
    int partBytes,
    AppLocalizations l10n,
  ) async {
    await _requestNotificationPermission();
    final directory = await _storage.getDownloadDirectory();
    if (directory == null) {
      throw StateError(l10n.unknownNetworkError);
    }
    final path = '$directory/${buildFileName(task)}';
    // The parts are joined into this file, and one already there would be
    // taken for the finished join.
    await _deleteOutput(path);
    final SingleStreamTransfer transfer;
    try {
      transfer = await _pairs.startSingleStream(
        taskId: task.id,
        title: task.title,
        url: task.downloadUrl,
        outputPath: path,
        partBytes: partBytes,
      );
    } on SlideshowException {
      await _enqueue(task, l10n);
      return;
    }
    // Confirming the length and queueing the parts took a moment, and a
    // cancel in that moment found no transfer to stop.
    final cancelled = task.status == DownloadStatus.cancelled;
    if (!cancelled) {
      task
        ..status = DownloadStatus.downloading
        ..filePath = path
        ..totalBytes = transfer.totalBytes
        ..errorMessage = null;
    }
    _watchParts(task, transfer);
    if (cancelled) _pairs.cancelStreamPair(task.id);
  }

  /// Follows [transfer] for [task] until its file is whole. [running] is
  /// false for a download found paused, which only waits to be resumed.
  void _watchParts(
    DownloadTask task,
    SingleStreamTransfer transfer, {
    bool running = true,
  }) {
    final id = task.id;
    _partTransfers[id] = transfer;
    if (running) _running.add(id);
    transfer.onProgress = (received, bytesPerSecond) {
      final total = transfer.totalBytes;
      final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
      final context = _contexts[id];
      if (context == null) {
        // Paused, so nobody is waiting on this download. What it shows is
        // what is kept, and a part that was all but there when the pause
        // came still lands.
        task
          ..progress = progress
          ..totalBytes = total
          ..receivedBytes = received
          ..downloadSpeed = 0;
        task.notifyProgressChanged();
        return;
      }
      final active = context.task;
      active
        ..status = DownloadStatus.downloading
        ..progress = progress
        ..totalBytes = total
        ..receivedBytes = received
        ..downloadSpeed = bytesPerSecond;
      context.onProgress(active, progress, received, total, bytesPerSecond);
    };
    unawaited(_finishParts(id, transfer));
  }

  Future<void> _finishParts(String id, SingleStreamTransfer transfer) async {
    try {
      final path = await transfer.file;
      transfer.onProgress = null;
      _partTransfers.remove(id);
      // Before the checks below: they read the file, not the parts.
      await _discardParts(transfer);
      if (_pausedParts.contains(id) && !_contexts.containsKey(id)) {
        // The last parts landed as the pause came. The download stays paused
        // as it is shown, and the resume has only to report the file.
        _wholeWhilePaused[id] = path;
        return;
      }
      if (_finishing.add(id)) await _complete(id, path);
    } on SlideshowException catch (error) {
      transfer.onProgress = null;
      _partTransfers.remove(id);
      _pausedParts.remove(id);
      await _discardParts(transfer);
      await _deleteOutput(transfer.outputPath);
      if (error.kind == SlideshowFailureKind.cancelled) {
        _contexts[id]?.task
          ?..status = DownloadStatus.cancelled
          ..downloadSpeed = 0;
        _finishAwait(id);
      } else {
        _fail(id, 'Download failed (${error.detail ?? error.kind.name})');
      }
    }
  }

  Future<void> _discardParts(SingleStreamTransfer transfer) =>
      transfer.discard().catchError((_) {});

  /// Removes a joined file and the unfinished one beside it.
  Future<void> _deleteOutput(String path) async {
    await PlatformFileHelper.deleteFile(path);
    await PlatformFileHelper.deleteFile('$path.part');
  }

  Future<void> _enqueue(DownloadTask task, AppLocalizations l10n) async {
    await _requestNotificationPermission();
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
    if (_pairs.owns(id)) {
      _pairs.handleUpdate(update);
      return;
    }
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
        if (_finishing.add(id)) {
          unawaited(update.task.filePath().then((path) => _complete(id, path)));
        }
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

  /// Checks the file a finished download left at [path] and reports it.
  Future<void> _complete(String id, String path) async {
    final context = _contexts[id];
    if (context == null) {
      _finishing.remove(id);
      return;
    }
    final task = context.task;
    try {
      final header = await PlatformFileHelper.readFileHeader(path, length: 512);
      final inspection = validator.inspect(header);
      if (inspection == null ||
          !validator.matchesExpectedKind(inspection, task.kind)) {
        throw FormatException(context.l10n.invalidDownloadedMedia);
      }
      final extension = validator.extensionFor(inspection, task.kind);
      if (extension.toLowerCase() != task.format.toLowerCase()) {
        final slash = path.lastIndexOf(_pathSeparator);
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
    final whole = _wholeWhilePaused.remove(taskId);
    if (whole != null) {
      _pausedParts.remove(taskId);
      unawaited(_deleteOutput(whole));
      return;
    }
    if (_partTransfers.containsKey(taskId)) {
      _pairs.cancelStreamPair(taskId);
      return;
    }
    unawaited(bg.FileDownloader().cancelTaskWithId(taskId));
  }

  @override
  bool pauseDownload(String taskId) {
    if (_partTransfers.containsKey(taskId)) {
      if (!_running.contains(taskId)) return false;
      _pausedParts.add(taskId);
      unawaited(_pairs.pause(taskId));
      _contexts[taskId]?.task
        ?..status = DownloadStatus.paused
        ..downloadSpeed = 0;
      _finishAwait(taskId);
      return true;
    }
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
