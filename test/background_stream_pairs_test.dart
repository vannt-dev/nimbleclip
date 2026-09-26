import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/merge_source.dart';
import 'package:nimble_clip/services/background_stream_pairs.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:nimble_clip/services/stream_pair_gateway.dart';

/// Stands in for background_downloader: remembers what was queued, and on
/// request writes a part's range of the stream to where the real one would
/// move the finished file.
class _FakeParts implements StreamPartDownloader {
  _FakeParts(this.streams);

  final Map<String, List<int>> streams;
  final List<bg.DownloadTask> queued = [];
  final List<String> cancelled = [];

  /// Ids the operating system still holds; queued tasks join it.
  final Set<String> known = {};

  @override
  Future<bool> enqueue(bg.DownloadTask task) async {
    queued.add(task);
    known.add(task.taskId);
    return true;
  }

  @override
  Future<void> cancel(Iterable<String> taskIds) async {
    cancelled.addAll(taskIds);
    known.removeAll(taskIds);
  }

  @override
  Future<bool> isKnown(String taskId) async => known.contains(taskId);

  /// Writes [task]'s range to disk, as a finished part, and returns the
  /// update background_downloader would send. [short] drops the last byte.
  Future<bg.TaskStatusUpdate> finish(
    bg.DownloadTask task, {
    bool short = false,
  }) async {
    final range = RegExp(
      r'bytes=(\d+)-(\d+)',
    ).firstMatch(task.headers['Range']!)!;
    final from = int.parse(range.group(1)!);
    final to = int.parse(range.group(2)!);
    final bytes = streams[task.url]!.sublist(from, to + 1);
    await File(
      '${task.directory}/${task.filename}',
    ).writeAsBytes(short ? bytes.sublist(1) : bytes);
    known.remove(task.taskId);
    return bg.TaskStatusUpdate(task, bg.TaskStatus.complete);
  }
}

const _videoUrl = 'https://yt.example/video';
const _audioUrl = 'https://yt.example/audio';
final _video = List<int>.generate(25, (i) => i);
final _audio = List<int>.generate(12, (i) => 100 + i);

void main() {
  late Directory root;
  late _FakeParts parts;

  setUp(() {
    root = Directory.systemTemp.createTempSync('stream_pairs');
    parts = _FakeParts({_videoUrl: _video, _audioUrl: _audio});
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  BackgroundStreamPairs pairs() => BackgroundStreamPairs(
    root: () async => root,
    downloader: parts,
    probeLength: (url) async => parts.streams[url]!.length,
    partBytes: 10,
  );

  Future<StreamPairTransfer> start(BackgroundStreamPairs gateway) =>
      gateway.startStreamPair(
        taskId: 'task-1',
        title: 'A video',
        source: const MergeSource(videoUrl: _videoUrl, audioUrl: _audioUrl),
        autoSaveToGallery: true,
      );

  Future<void> finishAll(
    BackgroundStreamPairs gateway,
    Iterable<bg.DownloadTask> tasks,
  ) async {
    for (final task in tasks.toList()) {
      gateway.handleUpdate(await parts.finish(task));
    }
  }

  group('planning parts', () {
    test('covers the stream in ranges no larger than a part', () {
      expect(planStreamParts(25, partBytes: 10), [
        (from: 0, to: 9),
        (from: 10, to: 19),
        (from: 20, to: 24),
      ]);
      expect(planStreamParts(20, partBytes: 10), [
        (from: 0, to: 9),
        (from: 10, to: 19),
      ]);
      expect(planStreamParts(0, partBytes: 10), isEmpty);
    });
  });

  group('fetching a pair', () {
    test('queues every part of both streams up front', () async {
      final gateway = pairs();
      final transfer = await start(gateway);

      expect(transfer.totalBytes, 37);
      expect(parts.queued.map((t) => t.headers['Range']), [
        'bytes=0-9',
        'bytes=10-19',
        'bytes=20-24',
        'bytes=0-9',
        'bytes=10-11',
      ]);
      expect(parts.queued.map((t) => t.url).toSet(), {_videoUrl, _audioUrl});
      expect(
        parts.queued.every((t) => t.group == streamPartGroup),
        isTrue,
        reason: 'the parts share one grouped notification',
      );
      expect(parts.queued.map((t) => t.taskId).every(gateway.owns), isTrue);
      final manifest = File('${root.path}/task-1/manifest.json');
      expect(manifest.existsSync(), isTrue);
    });

    test('joins each stream once every part has arrived', () async {
      final gateway = pairs();
      final transfer = await start(gateway);
      final reports = <int>[];
      transfer.onProgress = (received, _) => reports.add(received);

      await finishAll(gateway, parts.queued);
      final files = await transfer.files;

      expect(File(files.videoPath).readAsBytesSync(), _video);
      expect(File(files.audioPath).readAsBytesSync(), _audio);
      expect(reports.last, 37);
      // Only the joined streams and the manifest are left.
      expect(
        Directory(
          '${root.path}/task-1',
        ).listSync().map((e) => e.uri.pathSegments.last).toSet(),
        {'video.mp4', 'audio.m4a', 'manifest.json'},
      );
      expect(parts.queued.map((t) => t.taskId).any(gateway.owns), isFalse);
    });

    test('adds up progress across parts', () async {
      final gateway = pairs();
      final transfer = await start(gateway);
      final reports = <(int, double)>[];
      transfer.onProgress = (received, speed) => reports.add((received, speed));

      gateway.handleUpdate(
        bg.TaskProgressUpdate(parts.queued[0], 0.5, 10, 1.0),
      );
      gateway.handleUpdate(
        bg.TaskProgressUpdate(parts.queued[3], 0.2, 10, 0.5),
      );

      expect(reports.last.$1, 5 + 2);
      expect(reports.last.$2, 1.5 * 1024 * 1024);
    });

    test('a short part fails the pair and stops the rest', () async {
      final gateway = pairs();
      final transfer = await start(gateway);

      gateway.handleUpdate(await parts.finish(parts.queued[0], short: true));

      await expectLater(
        transfer.files,
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.fetchFailed,
          ),
        ),
      );
      expect(
        parts.cancelled,
        containsAll(parts.queued.skip(1).map((t) => t.taskId)),
      );
    });

    test('a failed part fails the pair', () async {
      final gateway = pairs();
      final transfer = await start(gateway);

      gateway.handleUpdate(
        bg.TaskStatusUpdate(
          parts.queued[1],
          bg.TaskStatus.failed,
          bg.TaskHttpException('Forbidden', 403),
        ),
      );

      await expectLater(
        transfer.files,
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.fetchFailed,
          ),
        ),
      );
      expect(parts.cancelled, hasLength(5));
    });

    test('a cancel stops every part', () async {
      final gateway = pairs();
      final transfer = await start(gateway);

      gateway.cancelStreamPair('task-1');

      await expectLater(
        transfer.files,
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.cancelled,
          ),
        ),
      );
      expect(parts.cancelled, parts.queued.map((t) => t.taskId));
    });

    test('discarding deletes everything the transfer wrote', () async {
      final gateway = pairs();
      final transfer = await start(gateway);
      await parts.finish(parts.queued[0]);

      await transfer.discard();

      expect(Directory('${root.path}/task-1').existsSync(), isFalse);
    });
  });

  group('recovering after the process ended', () {
    test(
      'keeps the parts that arrived and queues only the lost ones',
      () async {
        await start(pairs());
        final firstRun = List.of(parts.queued);
        // Two parts arrived while the app was gone; the rest were dropped, as a
        // force stop does, except one the system still holds.
        await parts.finish(firstRun[0]);
        await parts.finish(firstRun[3]);
        parts.known
          ..clear()
          ..add(firstRun[1].taskId);
        parts.queued.clear();

        final gateway = pairs();
        await gateway.recover();
        await gateway.requeueLostParts();
        final transfer = gateway.takeRecoveredStreamPairs().single;

        expect(transfer.taskId, 'task-1');
        expect(transfer.autoSaveToGallery, isTrue);
        expect(parts.queued.map((t) => t.taskId), [
          firstRun[2].taskId,
          firstRun[4].taskId,
        ]);
        await finishAll(gateway, [firstRun[1], ...parts.queued]);
        final files = await transfer.files;
        expect(File(files.videoPath).readAsBytesSync(), _video);
        expect(File(files.audioPath).readAsBytesSync(), _audio);
        expect(gateway.takeRecoveredStreamPairs(), isEmpty);
      },
    );

    test('joins straight away when every part already arrived', () async {
      await start(pairs());
      for (final task in List.of(parts.queued)) {
        await parts.finish(task);
      }
      parts.queued.clear();

      final gateway = pairs();
      await gateway.recover();
      await gateway.requeueLostParts();
      final transfer = gateway.takeRecoveredStreamPairs().single;

      expect(parts.queued, isEmpty);
      final files = await transfer.files;
      expect(File(files.videoPath).readAsBytesSync(), _video);
    });

    test('takes a joined stream as whole', () async {
      final transfer = await start(pairs());
      final gateway = pairs();
      final dir = '${root.path}/task-1';
      // The previous run joined the video, then ended before the audio.
      File('$dir/video.mp4').writeAsBytesSync(_video);
      for (final task in parts.queued.where((t) => t.url == _audioUrl)) {
        await parts.finish(task);
      }
      transfer.onProgress = null;
      parts.queued.clear();
      parts.known.clear();

      await gateway.recover();
      await gateway.requeueLostParts();
      final recovered = gateway.takeRecoveredStreamPairs().single;

      expect(parts.queued, isEmpty);
      final files = await recovered.files;
      expect(File(files.videoPath).readAsBytesSync(), _video);
      expect(File(files.audioPath).readAsBytesSync(), _audio);
    });

    test('fetches a part again when its file is not whole', () async {
      await start(pairs());
      final first = parts.queued.first;
      await parts.finish(first, short: true);
      parts.known.clear();
      parts.queued.clear();

      final gateway = pairs();
      await gateway.recover();
      await gateway.requeueLostParts();

      expect(parts.queued.map((t) => t.taskId), contains(first.taskId));
    });

    test('clears a directory without a manifest', () async {
      final stray = Directory('${root.path}/stray')..createSync();
      File('${stray.path}/v_0000').writeAsBytesSync([1, 2, 3]);

      final gateway = pairs();
      await gateway.recover();

      expect(stray.existsSync(), isFalse);
      expect(gateway.takeRecoveredStreamPairs(), isEmpty);
    });

    test('the manifest records what a later launch needs', () async {
      await start(pairs());
      final manifest =
          jsonDecode(
                File('${root.path}/task-1/manifest.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(manifest['video'], {'url': _videoUrl, 'total': 25});
      expect(manifest['audio'], {'url': _audioUrl, 'total': 12});
      expect(manifest['autoSaveToGallery'], isTrue);
    });
  });
}
