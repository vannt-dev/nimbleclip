import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/file_action_result.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/quality_descriptor_text.dart';
import '../core/utils/quality_helper.dart';
import '../models/download_task.dart';
import '../models/download_options.dart';
import '../models/merge_source.dart';
import '../models/slideshow_source.dart';
import '../models/video_metadata.dart';
import '../services/download_service.dart';
import '../services/slideshow/slideshow_asset_fetcher.dart';
import '../services/slideshow/slideshow_renderer.dart';
import '../services/slideshow/stream_fetcher.dart';
import '../services/background_download_service.dart';
import '../services/download_history_repository.dart';
import '../services/async_work_queue.dart';
import '../services/extractors/registry.dart';
import '../services/media_file_actions.dart';
import '../services/storage_service.dart';
import '../services/stream_pair_gateway.dart';

class DownloadProvider extends ChangeNotifier {
  DownloadProvider({
    DownloadGateway? downloadService,
    StorageService? storageService,
    DownloadHistoryRepository? historyRepository,
    MediaFileActions? fileActions,
    ExtractorRegistry? extractorRegistry,
    SlideshowRenderer? slideshowRenderer,
    Future<Directory> Function()? slideshowWorkspace,
    StreamFetcher? streamFetcher,
  }) : _downloadService = downloadService ?? createDefaultDownloadService(),
       _streamFetcher = streamFetcher ?? _defaultStreamFetcher,
       _storageService = storageService ?? StorageService(),
       _historyRepository =
           historyRepository ?? SharedPreferencesDownloadHistoryRepository(),
       _fileActions = fileActions ?? const PlatformMediaFileActions(),
       _slideshowRenderer = slideshowRenderer ?? createSlideshowRenderer(),
       _slideshowWorkspace = slideshowWorkspace ?? _defaultSlideshowWorkspace {
    _extractorRegistry = extractorRegistry ?? ExtractorRegistry();
    _queue = AsyncWorkQueue<_QueuedDownload>(
      worker: _executeQueued,
      shouldRun: (queued) =>
          queued.task.status == DownloadStatus.queued &&
          _tasks.contains(queued.task),
      maxConcurrent: defaultMaxConcurrentDownloads,
    );
    _historyReady = _loadHistory();
  }

  final List<DownloadTask> _tasks = [];
  final DownloadGateway _downloadService;
  final StorageService _storageService;
  final DownloadHistoryRepository _historyRepository;
  final MediaFileActions _fileActions;
  final SlideshowRenderer _slideshowRenderer;
  final Future<Directory> Function() _slideshowWorkspace;
  final StreamFetcher _streamFetcher;

  /// The option a rendered task was built from, so a retry can render it again
  /// rather than re-extracting it. In memory only: after a restart a finished
  /// render is just a file, and a failed one is redone from the post.
  final Map<String, VideoQualityOption> _renderOptions = {};

  /// Ids of renders currently running, so `cancelTask` knows which tasks the
  /// download queue cannot speak for.
  final Set<String> _slideshowRenders = {};

  late final ExtractorRegistry _extractorRegistry;
  final Uuid _uuid = const Uuid();
  late final Future<void> _historyReady;
  late final AsyncWorkQueue<_QueuedDownload> _queue;
  Future<void> _persistenceTail = Future.value();

  static const int defaultMaxConcurrentDownloads = 3;
  int get maxConcurrentDownloads => _queue.maxConcurrent;
  set maxConcurrentDownloads(int value) {
    _queue.maxConcurrent = value;
  }

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

  /// Count of in-flight tasks without materialising a list.
  ///
  /// The navigation badge selector reads this on every notification; going
  /// through `activeTasks.length` allocated a throwaway list each time just to
  /// read its length.
  int get activeTaskCount {
    var count = 0;
    for (final task in _tasks) {
      if (task.isActive) count++;
    }
    return count;
  }

  /// True when any task is still queued, running or paused. Used to gate
  /// destructive actions without building the three bucket lists.
  bool get hasUnfinishedTasks {
    for (final task in _tasks) {
      if (task.isActive || task.status == DownloadStatus.paused) return true;
    }
    return false;
  }

  /// True when at least one task has reached a terminal state.
  bool get hasFinishedTasks {
    for (final task in _tasks) {
      if (task.isDone) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _queue.clear();
    for (final task in _tasks) {
      task.dispose();
    }
    _downloadService.dispose();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  Future<void> _loadHistory() async {
    final loaded = await _historyRepository.loadHistory();
    _tasks
      ..clear()
      ..addAll(loaded);

    if (_downloadService is RecoverableDownloadGateway) {
      final recoverable = _downloadService as RecoverableDownloadGateway;
      final interrupted = loaded.where(
        (task) =>
            task.status == DownloadStatus.failed && task.errorMessage == null,
      );
      await recoverable.recoverDownloads(
        tasks: interrupted,
        onChanged: (_) => notifyListeners(),
        onTerminal: (task) {
          notifyListeners();
          unawaited(
            _saveHistory(
              receipt: task.status == DownloadStatus.completed ? task : null,
            ),
          );
        },
      );
    }
    _resumeMerges();
    for (final task in loaded) {
      // fromJson already demotes interrupted downloads to `failed`; give them a
      // message so the UI explains why they need a retry.
      if (task.status == DownloadStatus.failed && task.errorMessage == null) {
        task.errorMessage = 'download_interrupted';
      }
    }
    await _historyRepository.saveDownloadReceipts(
      loaded
          .where((task) => task.status == DownloadStatus.completed)
          .map((task) => task.toJson()),
    );
    notifyListeners();
  }

  /// Picks up the merges the previous process left fetching.
  ///
  /// Their parts kept arriving without the app, but joining them needs it. A
  /// merge whose task is gone, or is no longer the interrupted one, is thrown
  /// away rather than resumed.
  void _resumeMerges() {
    final gateway = _streamPairs;
    if (gateway == null) return;
    for (final transfer in gateway.takeRecoveredStreamPairs()) {
      final task = _findTask(transfer.taskId);
      if (task == null ||
          task.status != DownloadStatus.failed ||
          task.errorMessage != null) {
        unawaited(transfer.discard());
        continue;
      }
      task
        ..status = DownloadStatus.downloading
        ..progress = 0;
      // The locale is not known this early; history recovery reports in
      // English for the same reason.
      unawaited(
        _resumeMerge(
          task,
          transfer,
          lookupAppLocalizations(const Locale('en')),
        ),
      );
    }
  }

  Future<void> _saveHistory({DownloadTask? receipt}) {
    // `toJson` alone freezes the state; the previous `fromJson(toJson())` round
    // trip rebuilt a whole ChangeNotifier per task purely to throw it away
    // after serialization.
    final snapshot = _tasks
        .map((task) => task.toJson())
        .toList(growable: false);
    final receiptSnapshot = receipt?.toJson();
    _persistenceTail = _persistenceTail.then((_) async {
      if (receiptSnapshot != null) {
        await _historyRepository.saveDownloadReceipt(receiptSnapshot);
      }
      await _historyRepository.saveHistory(snapshot);
    });
    return _persistenceTail;
  }

  /// Finds selected media that already has a completed local or Gallery copy.
  /// The source option id is stable across re-analysis; older history entries
  /// fall back to quality and media kind when that id was not persisted.
  Future<List<DownloadTask>> findExistingDownloads({
    required VideoMetadata metadata,
    required List<VideoQualityOption> qualities,
    required AppLocalizations l10n,
  }) async {
    await _historyReady;
    final receipts = await _historyRepository.loadDownloadReceipts();
    final candidates = <String, DownloadTask>{
      for (final task in _tasks) task.id: task,
      // A receipt represents a verified device/Gallery copy and should win over
      // a visible history entry that may since have lost its app-local file.
      for (final receipt in receipts) receipt.id: receipt,
    }.values;
    final receiptIds = receipts.map((receipt) => receipt.id).toSet();
    final matches = <DownloadTask>[];
    final staleReceiptIds = <String>{};
    var historyChanged = false;

    for (final task in candidates) {
      if (task.status != DownloadStatus.completed ||
          !_matchesSelection(task, metadata, qualities, l10n)) {
        continue;
      }
      final localExists =
          task.filePath != null && _fileActions.exists(task.filePath!);
      var galleryExists = task.isSavedToGallery && task.filePath == null;
      if (task.isSavedToGallery && task.filePath != null) {
        final checked = await _fileActions.galleryExists(
          task.filePath!,
          isImage: task.isImage,
        );
        galleryExists = checked ?? true;
        if (checked == false) {
          task.isSavedToGallery = false;
          historyChanged = _tasks.contains(task) || historyChanged;
        }
      }
      if (localExists || galleryExists) {
        matches.add(task);
      } else if (receiptIds.contains(task.id)) {
        staleReceiptIds.add(task.id);
      }
    }

    if (staleReceiptIds.isNotEmpty) {
      await _historyRepository.removeDownloadReceipts(staleReceiptIds);
    }
    if (historyChanged) await _saveHistory();
    return matches;
  }

  /// Whether [quality] of [metadata] is already queued, running or paused.
  bool _isInFlight(
    VideoMetadata metadata,
    VideoQualityOption quality,
    AppLocalizations l10n,
  ) => _tasks.any(
    (task) =>
        (task.isActive || task.status == DownloadStatus.paused) &&
        _matchesSelection(task, metadata, [quality], l10n),
  );

  bool _matchesSelection(
    DownloadTask task,
    VideoMetadata metadata,
    List<VideoQualityOption> qualities,
    AppLocalizations l10n,
  ) {
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
      return task.qualityLabel == describeQuality(quality.label, l10n) &&
          task.kind == quality.kind;
    });
  }

  Future<List<DownloadTask>> startNewDownloads({
    required VideoMetadata metadata,
    required List<VideoQualityOption> qualities,
    required AppLocalizations l10n,
    DownloadOptions options = const DownloadOptions(),
  }) async {
    // Do not let the asynchronous history restore clear a task that the user
    // starts immediately after launch.
    await _historyReady;

    // A slideshow or a merged video has no single URL to fetch: it is produced
    // on the device first, and the finished file enters history as a file that
    // already exists. Splitting it off here keeps the URL path below untouched.
    final renderable = qualities
        .where((q) => q.needsRendering && !_isInFlight(metadata, q, l10n))
        .toList();
    if (renderable.isNotEmpty) {
      unawaited(_renderAll(renderable, metadata, l10n, options));
    }
    qualities = qualities.where((q) => !q.needsRendering).toList();

    if (qualities.isEmpty) return [];
    final pendingQualities = qualities.where(
      (quality) => !_isInFlight(metadata, quality, l10n),
    );
    final tasks = pendingQualities
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
            qualityLabel: describeQuality(quality.label, l10n),
            format: quality.format,
            kind: quality.kind,
            headers: quality.headers,
            totalBytes: quality.sizeBytes ?? 0,
          ),
        )
        .toList();

    if (tasks.isEmpty) return [];

    _tasks.insertAll(0, tasks.reversed);
    notifyListeners();
    await _saveHistory();

    for (final task in tasks) {
      _queue.add(_QueuedDownload(task: task, l10n: l10n, options: options));
    }
    return tasks;
  }

  /// Renders each slideshow or merged option in turn.
  ///
  /// Sequentially, not concurrently: a render holds a hardware encoder and the
  /// decoded frames of a 1080x1920 canvas, and two at once is how a mid-range
  /// device runs out of memory. A merge is lighter but fetches two large
  /// streams, which gain nothing from competing for the same connection.
  Future<void> _renderAll(
    List<VideoQualityOption> renderable,
    VideoMetadata metadata,
    AppLocalizations l10n,
    DownloadOptions options,
  ) async {
    for (final quality in renderable) {
      // Checked again per option: tasks are created one at a time, so a second
      // batch started meanwhile may already be producing this one.
      if (_isInFlight(metadata, quality, l10n)) continue;
      final task = DownloadTask(
        id: _uuid.v4(),
        videoId: metadata.id,
        title: metadata.title,
        author: metadata.author,
        thumbnailUrl: metadata.coverUrl,
        // The post is the closest thing a rendered file has to a source URL.
        // An empty one here is exactly the shape that would 404 if anything
        // ever fetched it, so the provenance goes in instead.
        downloadUrl: metadata.originalUrl,
        originalUrl: metadata.originalUrl,
        platform: metadata.platform,
        sourceOptionId: quality.id,
        qualityLabel: describeQuality(quality.label, l10n),
        format: quality.format,
        kind: quality.kind,
        totalBytes: quality.sizeBytes ?? 0,
        status: DownloadStatus.downloading,
      );
      _renderOptions[task.id] = quality;
      _tasks.insert(0, task);
      notifyListeners();
      // Persisted before anything runs: a merge fetches outside the app, and a
      // launch that finds its parts but not its task throws them away.
      await _saveHistory();
      await _render(task, quality, l10n, options);
    }
  }

  /// Clears the previous attempt off [task] and renders it again.
  Future<void> _retryRender(
    DownloadTask task,
    VideoQualityOption option,
    AppLocalizations l10n,
    DownloadOptions options,
  ) async {
    if (task.filePath != null) {
      await _fileActions.delete(task.filePath!);
    }
    task
      ..status = DownloadStatus.downloading
      ..progress = 0.0
      ..receivedBytes = 0
      ..errorMessage = null
      ..filePath = null;
    notifyListeners();
    // The stored failure has to go before the parts start: a launch resumes
    // only a merge whose task was interrupted, not one that had failed.
    await _saveHistory();
    await _render(task, option, l10n, options);
  }

  /// Produces [option]'s file in the download directory and records the
  /// result on [task].
  Future<void> _render(
    DownloadTask task,
    VideoQualityOption option,
    AppLocalizations l10n,
    DownloadOptions options,
  ) async {
    Directory? workspace;
    Future<Directory> scratch() async =>
        workspace ??= await _slideshowWorkspace();
    final merge = option.merge;
    try {
      await _produceRendered(
        task,
        l10n,
        isMerge: merge != null,
        autoSaveToGallery: options.autoSaveToGallery,
        produce: (outputPath) async {
          if (merge != null) {
            final gateway = _streamPairs;
            if (gateway == null) {
              final path = await _mergeStreams(
                task,
                merge,
                await scratch(),
                outputPath,
              );
              return (filePath: path, note: null);
            }
            final transfer = await gateway.startStreamPair(
              taskId: task.id,
              title: task.title,
              source: merge,
              autoSaveToGallery: options.autoSaveToGallery,
            );
            final path = await _muxTransfer(task, transfer, outputPath);
            return (filePath: path, note: null);
          }
          final result = await _renderSlideshow(
            task,
            option.slideshow!,
            await scratch(),
            outputPath,
          );
          // Music that could not be transcoded is a note on a finished
          // download, not a failure: the video is there and it plays.
          return (
            filePath: result.filePath,
            note: result.audioSkipped ? l10n.slideshowMusicUnavailable : null,
          );
        },
      );
    } finally {
      // Images and music are megabytes apiece; one leaked scratch directory
      // per render fills the cache up silently.
      final scratchDir = workspace;
      if (scratchDir != null) {
        try {
          if (scratchDir.existsSync()) scratchDir.deleteSync(recursive: true);
        } catch (_) {
          // A locked file is not worth failing a finished render over.
        }
      }
    }
  }

  /// Joins the streams of a merge the previous process left fetching.
  Future<void> _resumeMerge(
    DownloadTask task,
    StreamPairTransfer transfer,
    AppLocalizations l10n,
  ) => _produceRendered(
    task,
    l10n,
    isMerge: true,
    autoSaveToGallery: transfer.autoSaveToGallery,
    produce: (outputPath) async =>
        (filePath: await _muxTransfer(task, transfer, outputPath), note: null),
  );

  /// Runs [produce] against [task]'s file in the download directory and
  /// records the outcome on [task].
  ///
  /// Nothing here throws: a render is started without anyone awaiting it, so an
  /// escaping error would surface as an unhandled asynchronous exception with
  /// the task left stuck at `downloading` forever.
  Future<void> _produceRendered(
    DownloadTask task,
    AppLocalizations l10n, {
    required bool isMerge,
    required bool autoSaveToGallery,
    required Future<({String filePath, String? note})> Function(
      String outputPath,
    )
    produce,
  }) async {
    String? outputPath;
    _slideshowRenders.add(task.id);
    try {
      final downloadDir = await _storageService.getDownloadDirectory();
      if (downloadDir == null) {
        throw const SlideshowException(SlideshowFailureKind.encoderUnavailable);
      }
      // Rendered straight into its final home rather than moved there
      // afterwards: the temp and download directories can sit on different
      // filesystems, where a rename fails and a copy doubles the disk cost of
      // a file the encoder is already writing whole.
      outputPath = '$downloadDir/${_slideshowFileName(task)}';
      final result = await produce(outputPath);
      // A cancel that landed after the last cancellable step: the file is
      // whole, but the user asked not to have it.
      if (task.status == DownloadStatus.cancelled) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      task
        ..filePath = result.filePath
        ..status = DownloadStatus.completed
        ..progress = 1
        ..downloadSpeed = 0
        ..completedAt = DateTime.now()
        ..errorMessage = result.note;
      if (isMerge) {
        final size = await File(result.filePath).length();
        task
          ..totalBytes = size
          ..receivedBytes = size;
        if (autoSaveToGallery) {
          // Best effort, as for a fetched download: the file is complete in
          // the app either way, and Save to gallery stays on offer.
          await saveToGalleryManually(task).catchError((_) => false);
        }
      }
    } catch (error) {
      // A cancel is the user's own decision, already recorded on the task by
      // cancelTask. Overwriting it with `failed` would report their choice back
      // to them as an error.
      final cancelled =
          task.status == DownloadStatus.cancelled ||
          (error is SlideshowException &&
              error.kind == SlideshowFailureKind.cancelled);
      task
        ..status = cancelled ? DownloadStatus.cancelled : DownloadStatus.failed
        ..progress = 0
        ..downloadSpeed = 0
        ..filePath = null
        ..errorMessage = cancelled ? null : _slideshowFailureText(error, l10n);
      // A partial file would show up in the list as a playable download.
      if (outputPath != null) {
        await _fileActions.delete(outputPath).catchError((_) {});
      }
    } finally {
      _slideshowRenders.remove(task.id);
    }
    notifyListeners();
    await _saveHistory(
      receipt: task.status == DownloadStatus.completed ? task : null,
    );
  }

  Future<SlideshowResult> _renderSlideshow(
    DownloadTask task,
    SlideshowSource source,
    Directory workspace,
    String outputPath,
  ) async {
    final assets = await fetchSlideshowAssets(source, into: workspace);
    return _slideshowRenderer.render(
      imagePaths: assets.imagePaths,
      audioPath: assets.audioPath,
      perImage: source.perImage,
      width: source.width,
      height: source.height,
      outputPath: outputPath,
      renderId: task.id,
      onProgress: (fraction) => _reportRenderProgress(task, fraction),
    );
  }

  /// The gateway that fetches a merge's streams as operating-system
  /// transfers, when the platform has one; otherwise the streams are fetched
  /// here, and only while the app is running.
  StreamPairGateway? get _streamPairs {
    final gateway = _downloadService;
    return gateway is StreamPairGateway ? gateway as StreamPairGateway : null;
  }

  /// Share of a merged task's bar given to fetching; joining the two files
  /// only copies samples, so it takes the last sliver.
  static const double _mergeFetchShare = 0.95;

  /// Waits for [transfer]'s two streams and joins them at [outputPath].
  ///
  /// The transfer's files are deleted however this ends, except when the
  /// process itself ends part-way: then the next launch finishes the join.
  Future<String> _muxTransfer(
    DownloadTask task,
    StreamPairTransfer transfer,
    String outputPath,
  ) async {
    bool stopped() => task.status != DownloadStatus.downloading;
    try {
      // A cancel that landed while the parts were being queued found nothing
      // to stop yet.
      if (stopped()) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      task.totalBytes = transfer.totalBytes;
      transfer.onProgress = (received, bytesPerSecond) {
        if (stopped()) return;
        task
          ..receivedBytes = received
          ..downloadSpeed = bytesPerSecond
          ..progress = transfer.totalBytes > 0
              ? (received / transfer.totalBytes * _mergeFetchShare).clamp(
                  0.0,
                  _mergeFetchShare,
                )
              : 0.0;
        task.notifyProgressChanged();
      };
      final files = await transfer.files;
      if (stopped()) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      task.downloadSpeed = 0;
      return await _slideshowRenderer.mux(
        videoPath: files.videoPath,
        audioPath: files.audioPath,
        outputPath: outputPath,
        renderId: task.id,
        onProgress: (fraction) => _reportRenderProgress(
          task,
          _mergeFetchShare + fraction * (1 - _mergeFetchShare),
        ),
      );
    } finally {
      transfer.onProgress = null;
      await transfer.discard();
    }
  }

  /// Fetches [source]'s two streams into [workspace] and joins them at
  /// [outputPath].
  Future<String> _mergeStreams(
    DownloadTask task,
    MergeSource source,
    Directory workspace,
    String outputPath,
  ) async {
    final videoFile = File('${workspace.path}/video.mp4');
    final audioFile = File('${workspace.path}/audio.m4a');
    final expected = (source.videoBytes ?? 0) + (source.audioBytes ?? 0);
    bool stopped() => task.status != DownloadStatus.downloading;
    void reportBytes(int received) {
      if (stopped()) return;
      task.receivedBytes = received;
      if (expected > 0) {
        task.progress = (received / expected * _mergeFetchShare).clamp(
          0.0,
          _mergeFetchShare,
        );
      }
      task.notifyProgressChanged();
    }

    await _streamFetcher(
      source.videoUrl,
      videoFile,
      onBytes: reportBytes,
      isCancelled: stopped,
    );
    final videoReceived = await videoFile.length();
    await _streamFetcher(
      source.audioUrl,
      audioFile,
      onBytes: (received) => reportBytes(videoReceived + received),
      isCancelled: stopped,
    );
    if (stopped()) {
      throw const SlideshowException(SlideshowFailureKind.cancelled);
    }
    return _slideshowRenderer.mux(
      videoPath: videoFile.path,
      audioPath: audioFile.path,
      outputPath: outputPath,
      renderId: task.id,
      onProgress: (fraction) => _reportRenderProgress(
        task,
        _mergeFetchShare + fraction * (1 - _mergeFetchShare),
      ),
    );
  }

  void _reportRenderProgress(DownloadTask task, double fraction) {
    // Only while it is still running: a cancel already moved the task on, and
    // a late event would drag its bar back up.
    if (task.status != DownloadStatus.downloading) return;
    task.progress = fraction;
    task.notifyProgressChanged();
  }

  /// Mirrors the download services' naming so a rendered file sits alongside
  /// fetched ones rather than standing out in the folder.
  String _slideshowFileName(DownloadTask task) {
    final compactId = task.id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final idPart = compactId.isEmpty
        ? 'NimbleClip'
        : compactId.substring(0, compactId.length.clamp(0, 12));
    return '${task.platform.name}_$idPart.mp4';
  }

  String _slideshowFailureText(Object error, AppLocalizations l10n) {
    if (error is SlideshowException) {
      return switch (error.kind) {
        SlideshowFailureKind.outOfSpace => l10n.slideshowOutOfSpace,
        SlideshowFailureKind.fetchFailed => l10n.downloadFailed,
        _ => l10n.slideshowRenderFailed,
      };
    }
    return l10n.slideshowRenderFailed;
  }

  Future<void> _executeQueued(_QueuedDownload queued) =>
      _executeDownload(queued.task, l10n: queued.l10n, options: queued.options);

  Future<void> _executeDownload(
    DownloadTask task, {
    required AppLocalizations l10n,
    DownloadOptions options = const DownloadOptions(),
  }) async {
    await _downloadService.startDownload(
      task: task,
      l10n: l10n,
      autoSaveToGallery: options.autoSaveToGallery,
      onProgress: (changedTask, _, _, _, _) =>
          changedTask.notifyProgressChanged(),
      onComplete: (_, _) {
        notifyListeners();
      },
      onError: (_, _) {
        notifyListeners();
      },
    );
    final localPath = task.filePath;
    if (task.status == DownloadStatus.completed &&
        task.isSavedToGallery &&
        !task.isAudioOnly &&
        localPath != null) {
      task.galleryUri = await _fileActions.galleryUri(
        localPath,
        isImage: task.isImage,
      );
      // Only remove the app-local copy when Android returned a durable
      // MediaStore URI. This keeps Open/Share functional and avoids data loss
      // on platforms where Gallery cannot be addressed directly.
      if (options.removeCacheAfterGallery && task.galleryUri != null) {
        await _fileActions.delete(localPath);
        task.filePath = null;
      }
    }
    // Covers the pause / cancel paths, which finish without a callback.
    notifyListeners();
    await _saveHistory(
      receipt: task.status == DownloadStatus.completed ? task : null,
    );
  }

  void cancelTask(String taskId) {
    _queue.removeWhere((queued) => queued.task.id == taskId);
    // A render never entered the queue and the download gateway has never
    // heard of it, so neither line below can stop one. Only the renderer can,
    // and it has to be told before the status is set: the render's own catch
    // reads that status to tell a cancel apart from a failure.
    _stopRender(taskId);
    _downloadService.cancelDownload(taskId);
    final task = _findTask(taskId);
    if (task == null) return;
    task.status = DownloadStatus.cancelled;
    task.downloadSpeed = 0.0;
    notifyListeners();
    unawaited(_saveHistory());
  }

  /// Stops a running render or merge, including any stream parts still
  /// arriving outside the app.
  void _stopRender(String taskId) {
    if (!_slideshowRenders.contains(taskId)) return;
    unawaited(_slideshowRenderer.cancel(taskId));
    _streamPairs?.cancelStreamPair(taskId);
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
    DownloadOptions options = const DownloadOptions(),
  }) async {
    if (task.status != DownloadStatus.paused) return;
    task.status = DownloadStatus.queued;
    task.errorMessage = null;
    notifyListeners();
    _queue.add(_QueuedDownload(task: task, l10n: l10n, options: options));
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
    DownloadOptions options = const DownloadOptions(),
    required AppLocalizations l10n,
  }) async {
    // A rendered task has no URL to re-fetch. Re-extracting it hands back the
    // slideshow option, whose downloadUrl is empty by construction, and the
    // queue below would then try to download nothing at all.
    //
    // The remembered source is only a shortcut past that round trip. It cannot
    // be the whole answer: the map lives in memory, while a failed task is
    // persisted and comes back on the next launch, so a retry after a restart
    // has to fall through to re-extraction — see `_retrySlideshow`.
    //
    // A merged YouTube option is the exception to the shortcut: its stream
    // URLs are signed and expire within hours, so it is always re-extracted.
    final remembered = _renderOptions[task.id];
    if (remembered != null && remembered.merge == null) {
      await _retryRender(task, remembered, l10n, options);
      return;
    }

    task.status = DownloadStatus.queued;
    task.progress = 0.0;
    task.receivedBytes = 0;
    task.downloadSpeed = 0.0;
    task.errorMessage = null;
    notifyListeners();

    if (task.filePath != null) {
      await _fileActions.delete(task.filePath!);
    }

    final refreshedUrl = await _refreshDownloadUrl(task, l10n);

    // Re-extraction is what makes a retry survive a restart: the option comes
    // back with a live source, even though nothing about the stored task could
    // have said how to render it.
    if (refreshedUrl != null && refreshedUrl.needsRendering) {
      _renderOptions[task.id] = refreshedUrl;
      await _retryRender(task, refreshedUrl, l10n, options);
      return;
    }
    if (refreshedUrl == null && remembered != null) {
      // Re-extraction failed; the remembered streams are the only lead left.
      await _retryRender(task, remembered, l10n, options);
      return;
    }

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
        _QueuedDownload(task: refreshed, l10n: l10n, options: options),
      );
      await _saveHistory();
      return;
    }

    _queue.add(_QueuedDownload(task: task, l10n: l10n, options: options));
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
      final metadata = await _extractorRegistry.extract(task.originalUrl);
      if (task.sourceOptionId.isNotEmpty) {
        for (final option in metadata.qualities) {
          if (option.id == task.sourceOptionId) return option;
        }
      }
      for (final option in metadata.qualities) {
        if (describeQuality(option.label, l10n) == task.qualityLabel) {
          return option;
        }
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
    if (_slideshowRenders.contains(taskId)) {
      _stopRender(taskId);
      // Silences the render's progress callbacks, which only report while a
      // task is downloading; the task is disposed below.
      task.status = DownloadStatus.cancelled;
    }
    if (deleteLocalFile && task.filePath != null) {
      await _fileActions.delete(task.filePath!);
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
        await _fileActions.delete(task.filePath!);
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
    if (hasUnfinishedTasks) return false;
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
    if (task.filePath == null || task.isAudioOnly) return false;
    final success = await _storageService.saveToGallery(
      task.filePath!,
      isAudio: task.isAudioOnly,
      isImage: task.isImage,
    );
    if (success) {
      task.isSavedToGallery = true;
      task.galleryUri = await _fileActions.galleryUri(
        task.filePath!,
        isImage: task.isImage,
      );
      notifyListeners();
      await _saveHistory(receipt: task);
    }
    return success;
  }

  Future<bool> ensureLocalFileAvailable(DownloadTask task) async {
    await _historyReady;
    final filePath = task.filePath;
    if (filePath != null && _fileActions.exists(filePath)) {
      return true;
    }
    await _markLocalFileMissing(task);
    return false;
  }

  Future<FileActionResult> openFile(DownloadTask task) async {
    if (task.galleryUri != null &&
        (task.filePath == null || !_fileActions.exists(task.filePath!))) {
      return _fileActions.openGallery(task.galleryUri!);
    }
    if (!await ensureLocalFileAvailable(task)) {
      return FileActionResult.fileMissing;
    }
    final result = await _fileActions.openLocal(task.filePath!);
    if (result == FileActionResult.fileMissing) {
      await _markLocalFileMissing(task);
    }
    return result;
  }

  Future<FileActionResult> shareFile(DownloadTask task, String message) async {
    if (task.galleryUri != null &&
        (task.filePath == null || !_fileActions.exists(task.filePath!))) {
      return _fileActions.shareGallery(task.galleryUri!, text: message);
    }
    if (!await ensureLocalFileAvailable(task)) {
      return FileActionResult.fileMissing;
    }
    final result = await _fileActions.shareLocal(task.filePath!, text: message);
    if (result == FileActionResult.fileMissing) {
      await _markLocalFileMissing(task);
    }
    return result;
  }

  Future<void> _markLocalFileMissing(DownloadTask task) async {
    final missingPath = task.filePath;
    task
      ..status = DownloadStatus.failed
      ..errorMessage = 'local_file_missing'
      ..filePath = null
      ..downloadSpeed = 0;

    var galleryStillExists = false;
    if (task.isSavedToGallery && !task.isAudioOnly && missingPath != null) {
      final checked = await _fileActions.galleryExists(
        missingPath,
        isImage: task.isImage,
      );
      galleryStillExists = checked ?? true;
      if (checked == false) {
        task.isSavedToGallery = false;
      }
    }
    if (!galleryStillExists) {
      await _historyRepository.removeDownloadReceipts({task.id});
    }
    notifyListeners();
    await _saveHistory();
  }

  DownloadTask? _findTask(String taskId) {
    for (final task in _tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }
}

/// A fresh scratch directory under the OS temp directory, one per render, so
/// two runs of the same post cannot read each other's half-written images.
/// Fetches one stream of a merged video to a local file; injectable so tests
/// can stand in for the network.
typedef StreamFetcher =
    Future<void> Function(
      String url,
      File into, {
      void Function(int receivedBytes)? onBytes,
      bool Function()? isCancelled,
    });

Future<void> _defaultStreamFetcher(
  String url,
  File into, {
  void Function(int receivedBytes)? onBytes,
  bool Function()? isCancelled,
}) => fetchStreamToFile(url, into, onBytes: onBytes, isCancelled: isCancelled);

Future<Directory> _defaultSlideshowWorkspace() async {
  final temp = await getTemporaryDirectory();
  return Directory(
    '${temp.path}/slideshow_${DateTime.now().microsecondsSinceEpoch}',
  )..createSync(recursive: true);
}

class _QueuedDownload {
  const _QueuedDownload({
    required this.task,
    required this.l10n,
    required this.options,
  });

  final DownloadTask task;
  final AppLocalizations l10n;
  final DownloadOptions options;
}
