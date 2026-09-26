import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;

import '../models/merge_source.dart';
import 'slideshow/slideshow_failure.dart';
import 'slideshow/stream_fetcher.dart';
import 'stream_pair_gateway.dart';

/// The largest range fetched in one request. YouTube serves a range of this
/// size at full speed but throttles anything larger, or open-ended, to roughly
/// playback speed.
const int streamPartBytes = 10 << 20;

/// The background_downloader group every stream part belongs to, so they share
/// one notification rather than posting one each.
const String streamPartGroup = 'stream_parts';

/// Byte ranges, inclusive, covering [total] bytes in parts of at most
/// [partBytes].
List<({int from, int to})> planStreamParts(
  int total, {
  int partBytes = streamPartBytes,
}) => [
  for (var from = 0; from < total; from += partBytes)
    (from: from, to: (from + partBytes < total ? from + partBytes : total) - 1),
];

/// What the background downloader offers the stream parts, narrowed so tests
/// can stand in for the native side.
abstract interface class StreamPartDownloader {
  Future<bool> enqueue(bg.DownloadTask task);
  Future<void> cancel(Iterable<String> taskIds);

  /// Whether the operating system still holds [taskId], queued or running.
  Future<bool> isKnown(String taskId);
}

class NativeStreamPartDownloader implements StreamPartDownloader {
  const NativeStreamPartDownloader();

  @override
  Future<bool> enqueue(bg.DownloadTask task) =>
      bg.FileDownloader().enqueue(task);

  @override
  Future<void> cancel(Iterable<String> taskIds) =>
      bg.FileDownloader().cancelTasksWithIds(taskIds);

  @override
  Future<bool> isKnown(String taskId) async =>
      await bg.FileDownloader().taskForId(taskId) != null;
}

/// Fetches merged videos' streams as ranged background_downloader tasks, one
/// per [streamPartBytes], all queued up front.
///
/// background_downloader's own `ParallelDownloadTask` is no substitute: it
/// relies on the Flutter engine to queue its parts and to relay their progress,
/// so it stalls as soon as the process is gone. Plain tasks each run on their
/// own; the app only has to be there to join the parts.
///
/// Each transfer keeps a manifest beside its parts. That, and the parts on
/// disk, is all a later launch needs: background_downloader writes a part to a
/// temporary file and moves it into place only once it is whole, so a part's
/// file existing means it has arrived.
class BackgroundStreamPairs implements StreamPairGateway {
  BackgroundStreamPairs({
    required this._root,
    this._downloader = const NativeStreamPartDownloader(),
    Future<int> Function(String url)? probeLength,
    this.partBytes = streamPartBytes,
  }) : _probeLength = probeLength ?? probeStreamLength;

  final Future<Directory> Function() _root;
  final StreamPartDownloader _downloader;
  final Future<int> Function(String url) _probeLength;
  final int partBytes;

  final Map<String, _PairTransfer> _transfers = {};
  final Map<String, _Part> _parts = {};
  final List<_PairTransfer> _recovered = [];

  /// Whether [taskId] is one of the parts this class queued.
  bool owns(String taskId) => _parts.containsKey(taskId);

  @override
  Future<StreamPairTransfer> startStreamPair({
    required String taskId,
    required String title,
    required MergeSource source,
    required bool autoSaveToGallery,
  }) async {
    final lengths = await Future.wait([
      _probeLength(source.videoUrl),
      _probeLength(source.audioUrl),
    ]);
    final manifest = _Manifest(
      taskId: taskId,
      title: title,
      autoSaveToGallery: autoSaveToGallery,
      partBytes: partBytes,
      video: (url: source.videoUrl, total: lengths[0]),
      audio: (url: source.audioUrl, total: lengths[1]),
    );
    final directory = Directory('${(await _root()).path}/$taskId');
    try {
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$_manifestName',
      ).writeAsString(jsonEncode(manifest.toJson()), flush: true);
    } on FileSystemException catch (error) {
      await _deleteQuietly(directory);
      throw _fileFailure(error);
    }
    final transfer = _register(manifest, directory);
    for (final part in transfer.parts) {
      if (!await _downloader.enqueue(part.task)) {
        transfer.fail(
          const SlideshowException(
            SlideshowFailureKind.fetchFailed,
            detail: 'a stream part could not be queued',
          ),
        );
        break;
      }
    }
    return transfer;
  }

  /// Rebuilds the transfers an earlier process left behind.
  ///
  /// Must run before background_downloader replays the updates it collected
  /// while the app was gone, or updates for these parts land nowhere.
  Future<void> recover() async {
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final manifestFile = File('${entry.path}/$_manifestName');
      _Manifest? manifest;
      try {
        manifest = _Manifest.fromJson(
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {
        manifest = null;
      }
      // Without a manifest there is nothing to finish: the transfer never got
      // as far as queueing its parts.
      if (manifest == null || _transfers.containsKey(manifest.taskId)) {
        await _deleteQuietly(entry);
        continue;
      }
      final transfer = _register(manifest, entry);
      for (final part in transfer.parts) {
        if (await transfer.isStreamJoined(part.stream)) {
          part.done = true;
          continue;
        }
        final file = File(part.path);
        if (!await file.exists()) continue;
        if (await file.length() == part.bytes) {
          part.done = true;
        } else {
          // Not a part background_downloader finished; fetch it again.
          await file.delete();
        }
      }
      _recovered.add(transfer);
    }
  }

  /// Queues again any part of a recovered transfer that is neither on disk nor
  /// still held by the operating system — a force stop, for one, drops every
  /// queued task. Runs once background_downloader has replayed its updates.
  Future<void> requeueLostParts() async {
    for (final transfer in List.of(_recovered)) {
      await transfer.finishIfWhole();
      for (final part in transfer.parts) {
        if (transfer.isSettled) break;
        if (part.done || await _downloader.isKnown(part.task.taskId)) continue;
        if (!await _downloader.enqueue(part.task)) {
          transfer.fail(
            const SlideshowException(
              SlideshowFailureKind.fetchFailed,
              detail: 'a stream part could not be queued again',
            ),
          );
        }
      }
    }
  }

  @override
  List<StreamPairTransfer> takeRecoveredStreamPairs() {
    final taken = List<StreamPairTransfer>.of(_recovered);
    _recovered.clear();
    return taken;
  }

  @override
  void cancelStreamPair(String taskId) {
    final transfer = _transfers[taskId];
    if (transfer == null) return;
    transfer.fail(const SlideshowException(SlideshowFailureKind.cancelled));
  }

  /// Applies a background_downloader update for one of [owns]'s parts.
  void handleUpdate(bg.TaskUpdate update) {
    final part = _parts[update.task.taskId];
    if (part == null) return;
    final transfer = part.transfer;
    if (update is bg.TaskProgressUpdate) {
      if (update.progress < 0) return;
      part
        ..fraction = update.progress.clamp(0.0, 1.0)
        ..bytesPerSecond = update.hasNetworkSpeed
            ? update.networkSpeed * 1024 * 1024
            : 0;
      transfer.reportProgress();
      return;
    }
    if (update is! bg.TaskStatusUpdate) return;
    switch (update.status) {
      case bg.TaskStatus.complete:
        unawaited(transfer.partArrived(part));
      case bg.TaskStatus.failed:
      case bg.TaskStatus.notFound:
        transfer.fail(
          SlideshowException(
            SlideshowFailureKind.fetchFailed,
            detail:
                update.exception?.description ??
                'HTTP ${update.responseStatusCode ?? 'unknown'}',
          ),
        );
      case bg.TaskStatus.canceled:
        transfer.fail(const SlideshowException(SlideshowFailureKind.cancelled));
      case bg.TaskStatus.enqueued:
      case bg.TaskStatus.running:
      case bg.TaskStatus.waitingToRetry:
      case bg.TaskStatus.paused:
        break;
    }
  }

  _PairTransfer _register(_Manifest manifest, Directory directory) {
    final transfer = _PairTransfer(
      manifest: manifest,
      directory: directory,
      onSettled: _forget,
      cancelParts: _downloader.cancel,
    );
    _transfers[manifest.taskId] = transfer;
    for (final part in transfer.parts) {
      _parts[part.task.taskId] = part;
    }
    return transfer;
  }

  void _forget(_PairTransfer transfer) {
    _transfers.remove(transfer.taskId);
    for (final part in transfer.parts) {
      _parts.remove(part.task.taskId);
    }
  }
}

const String _manifestName = 'manifest.json';

typedef _StreamPlan = ({String url, int total});

enum _Stream {
  video('v', 'video.mp4'),
  audio('a', 'audio.m4a');

  const _Stream(this.tag, this.fileName);

  final String tag;
  final String fileName;
}

class _Manifest {
  const _Manifest({
    required this.taskId,
    required this.title,
    required this.autoSaveToGallery,
    required this.partBytes,
    required this.video,
    required this.audio,
  });

  factory _Manifest.fromJson(Map<String, dynamic> json) {
    _StreamPlan plan(Object? raw) {
      final map = raw! as Map<String, dynamic>;
      return (url: map['url']! as String, total: map['total']! as int);
    }

    return _Manifest(
      taskId: json['taskId']! as String,
      title: json['title'] as String? ?? '',
      autoSaveToGallery: json['autoSaveToGallery'] as bool? ?? false,
      partBytes: json['partBytes']! as int,
      video: plan(json['video']),
      audio: plan(json['audio']),
    );
  }

  final String taskId;
  final String title;
  final bool autoSaveToGallery;
  final int partBytes;
  final _StreamPlan video;
  final _StreamPlan audio;

  _StreamPlan plan(_Stream stream) => switch (stream) {
    _Stream.video => video,
    _Stream.audio => audio,
  };

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'title': title,
    'autoSaveToGallery': autoSaveToGallery,
    'partBytes': partBytes,
    'video': {'url': video.url, 'total': video.total},
    'audio': {'url': audio.url, 'total': audio.total},
  };
}

class _Part {
  _Part({
    required this.transfer,
    required this.stream,
    required this.task,
    required this.path,
    required this.bytes,
  });

  final _PairTransfer transfer;
  final _Stream stream;
  final bg.DownloadTask task;
  final String path;
  final int bytes;
  bool done = false;
  double fraction = 0;
  double bytesPerSecond = 0;
}

class _PairTransfer implements StreamPairTransfer {
  _PairTransfer({
    required this.manifest,
    required this.directory,
    required this._onSettled,
    required this._cancelParts,
  }) {
    // A transfer can fail before anyone awaits it — a recovered one waits for
    // the provider — and an unheard failure would surface as an uncaught
    // error. Whoever does await [files] still receives it.
    _files.future.ignore();
    for (final stream in _Stream.values) {
      final plan = manifest.plan(stream);
      final ranges = planStreamParts(plan.total, partBytes: manifest.partBytes);
      for (var i = 0; i < ranges.length; i++) {
        final range = ranges[i];
        final fileName = '${stream.tag}_${i.toString().padLeft(4, '0')}';
        parts.add(
          _Part(
            transfer: this,
            stream: stream,
            path: '${directory.path}/$fileName',
            bytes: range.to - range.from + 1,
            task: bg.DownloadTask(
              taskId: '${manifest.taskId}~${stream.tag}~$i',
              url: plan.url,
              filename: fileName,
              directory: directory.path,
              baseDirectory: bg.BaseDirectory.root,
              headers: {'Range': 'bytes=${range.from}-${range.to}'},
              group: streamPartGroup,
              updates: bg.Updates.statusAndProgress,
              retries: 3,
              displayName: manifest.title,
              metaData: manifest.taskId,
            ),
          ),
        );
      }
    }
  }

  final _Manifest manifest;
  final Directory directory;
  final void Function(_PairTransfer) _onSettled;
  final Future<void> Function(Iterable<String>) _cancelParts;
  final List<_Part> parts = [];
  final Completer<StreamPairFiles> _files = Completer<StreamPairFiles>();
  bool _joining = false;

  void Function(int receivedBytes, double bytesPerSecond)? _onProgress;

  @override
  String get taskId => manifest.taskId;

  @override
  bool get autoSaveToGallery => manifest.autoSaveToGallery;

  @override
  int get totalBytes => manifest.video.total + manifest.audio.total;

  @override
  Future<StreamPairFiles> get files => _files.future;

  @override
  set onProgress(void Function(int receivedBytes, double bytesPerSecond)? cb) {
    _onProgress = cb;
    if (cb != null) reportProgress();
  }

  bool get isSettled => _files.isCompleted;

  String _joinedPath(_Stream stream) => '${directory.path}/${stream.fileName}';

  Future<bool> isStreamJoined(_Stream stream) =>
      File(_joinedPath(stream)).exists();

  void reportProgress() {
    final report = _onProgress;
    if (report == null || isSettled) return;
    var received = 0;
    var speed = 0.0;
    for (final part in parts) {
      if (part.done) {
        received += part.bytes;
      } else {
        received += (part.bytes * part.fraction).round();
        speed += part.bytesPerSecond;
      }
    }
    report(received, speed);
  }

  Future<void> partArrived(_Part part) async {
    if (isSettled) return;
    final File file = File(part.path);
    // A part cut short would shift every byte after it and leave a stream the
    // muxer cannot read, so its length is checked before it counts.
    final length = await file.exists() ? await file.length() : -1;
    if (length != part.bytes) {
      fail(
        SlideshowException(
          SlideshowFailureKind.fetchFailed,
          detail: 'part ${part.task.taskId} is $length of ${part.bytes} bytes',
        ),
      );
      return;
    }
    part
      ..done = true
      ..fraction = 1
      ..bytesPerSecond = 0;
    reportProgress();
    await finishIfWhole();
  }

  /// Joins each stream's parts once all of them are on disk.
  Future<void> finishIfWhole() async {
    if (isSettled || _joining || parts.any((part) => !part.done)) return;
    _joining = true;
    try {
      for (final stream in _Stream.values) {
        await _join(stream);
      }
      if (isSettled) return;
      _files.complete((
        videoPath: _joinedPath(_Stream.video),
        audioPath: _joinedPath(_Stream.audio),
      ));
      _onSettled(this);
    } on FileSystemException catch (error) {
      fail(_fileFailure(error));
    } finally {
      _joining = false;
    }
  }

  /// Concatenates [stream]'s parts into one file, deleting each part once the
  /// whole is in place.
  ///
  /// Written under a temporary name and renamed at the end, so a process
  /// ended mid-join leaves either every part or the finished stream — never a
  /// short file a later launch would mistake for the whole.
  Future<void> _join(_Stream stream) async {
    final joined = File(_joinedPath(stream));
    final streamParts = parts.where((part) => part.stream == stream).toList();
    if (!await joined.exists()) {
      final partial = File('${joined.path}.part');
      final sink = partial.openWrite();
      try {
        for (final part in streamParts) {
          await sink.addStream(File(part.path).openRead());
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      await partial.rename(joined.path);
    }
    for (final part in streamParts) {
      final file = File(part.path);
      if (await file.exists()) await file.delete();
    }
  }

  /// Ends the transfer with [error], stopping any part still running.
  void fail(SlideshowException error) {
    if (isSettled) return;
    _files.completeError(error);
    // Parts that already arrived have nothing left to stop.
    final running = parts.where((part) => !part.done).map((p) => p.task.taskId);
    unawaited(_cancelParts(running.toList()).catchError((_) {}));
    _onSettled(this);
  }

  @override
  Future<void> discard() async {
    fail(const SlideshowException(SlideshowFailureKind.cancelled));
    await _deleteQuietly(directory);
  }
}

SlideshowException _fileFailure(FileSystemException error) =>
    SlideshowException(
      isOutOfSpace(error)
          ? SlideshowFailureKind.outOfSpace
          : SlideshowFailureKind.fetchFailed,
      detail: error.toString(),
    );

Future<void> _deleteQuietly(Directory directory) async {
  try {
    if (await directory.exists()) await directory.delete(recursive: true);
  } catch (_) {
    // A locked file is not worth failing over; the next recovery retries.
  }
}
