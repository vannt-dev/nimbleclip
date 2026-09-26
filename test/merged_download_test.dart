import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nimble_clip/core/utils/quality_helper.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/merge_source.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/extractors/youtube_extractor.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:nimble_clip/services/slideshow/stream_fetcher.dart';
import 'package:nimble_clip/services/stream_pair_gateway.dart';

import 'support/inert_download_service.dart';
import 'support/memory_storage.dart';

/// Stands in for the platform muxer: records what it was asked to join and
/// writes the two inputs back to back, so the output can be asserted on.
class _FakeMuxer implements SlideshowRenderer {
  _FakeMuxer({this.failWith});

  final SlideshowFailureKind? failWith;
  final List<({String video, String audio, String output})> calls = [];
  final List<String> cancelledIds = [];

  @override
  bool get isSupported => true;

  @override
  Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    String? renderId,
    void Function(double progress)? onProgress,
  }) async {
    calls.add((video: videoPath, audio: audioPath, output: outputPath));
    final failure = failWith;
    if (failure != null) throw SlideshowException(failure);
    onProgress?.call(0.5);
    await File(outputPath).writeAsBytes([
      ...File(videoPath).readAsBytesSync(),
      ...File(audioPath).readAsBytesSync(),
    ]);
    onProgress?.call(1);
    return outputPath;
  }

  @override
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
    String? renderId,
    void Function(double progress)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancel(String renderId) async => cancelledIds.add(renderId);
}

/// Serves each URL's bytes from a table; a URL in [blocking] waits until the
/// fetch is cancelled, so the cancel path does not race a fast fake.
class _FakeFetcher {
  _FakeFetcher(this.bodies, {this.blocking = const {}});

  final Map<String, List<int>> bodies;
  final Set<String> blocking;
  final List<String> fetched = [];

  Future<void> call(
    String url,
    File into, {
    void Function(int receivedBytes)? onBytes,
    bool Function()? isCancelled,
  }) async {
    fetched.add(url);
    if (blocking.contains(url)) {
      while (!(isCancelled?.call() ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      throw const SlideshowException(SlideshowFailureKind.cancelled);
    }
    final body = bodies[url];
    if (body == null) {
      throw const SlideshowException(SlideshowFailureKind.fetchFailed);
    }
    await into.writeAsBytes(body);
    onBytes?.call(body.length);
  }
}

class _FixedRegistry extends ExtractorRegistry {
  _FixedRegistry(this.metadata);

  final VideoMetadata metadata;
  int calls = 0;

  @override
  Future<VideoMetadata> extract(String rawUrl) async {
    calls++;
    return metadata;
  }
}

VideoQualityOption _merged({
  String id = 'yt_merged_137',
  String video = 'https://yt.example/video-1080',
  String audio = 'https://yt.example/audio',
}) => VideoQualityOption.merged(
  id: id,
  label: const VideoWithAudio('1080p'),
  quality: '1080p',
  sizeBytes: 5,
  source: MergeSource(
    videoUrl: video,
    audioUrl: audio,
    videoBytes: 3,
    audioBytes: 2,
  ),
);

VideoMetadata _metadata(List<VideoQualityOption> qualities) => VideoMetadata(
  id: 'dQw4w9WgXcQ',
  originalUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  title: 'A video',
  author: 'Author',
  coverUrl: 'https://img.example/cover.jpg',
  platform: VideoPlatform.youtube,
  qualities: qualities,
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

AdaptiveStream _stream(
  int tag,
  String label,
  int height, {
  String container = 'mp4',
  String codecs = 'avc1.640028',
  int bitrate = 1000,
}) => AdaptiveStream(
  tag: tag,
  qualityLabel: label,
  height: height,
  container: container,
  codecs: codecs,
  url: 'https://yt.example/$tag',
  bytes: tag * 10,
  bitrate: bitrate,
);

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('choosing merged qualities', () {
    const audio = AdaptiveStream(
      tag: 140,
      qualityLabel: '',
      height: 0,
      container: 'mp4',
      codecs: 'mp4a.40.2',
      url: 'https://yt.example/140',
      bytes: 7,
      bitrate: 128000,
    );

    test('offers H.264 above the muxed quality, up to 1080p', () {
      final options = YouTubeExtractor.planMergedOptions(
        videos: [
          _stream(401, '2160p', 2160, codecs: 'av01.0.12M.08'),
          _stream(271, '1440p', 1440, container: 'webm', codecs: 'vp9'),
          _stream(248, '1080p', 1080, container: 'webm', codecs: 'vp9'),
          _stream(136, '720p', 720),
          _stream(137, '1080p', 1080),
          _stream(135, '480p', 480),
          _stream(134, '360p', 360),
        ],
        audio: audio,
        aboveHeight: 360,
      );

      expect(options.map((o) => o.id), [
        'yt_merged_137',
        'yt_merged_136',
        'yt_merged_135',
      ]);
      final best = options.first;
      expect(best.merge!.videoUrl, 'https://yt.example/137');
      expect(best.merge!.audioUrl, 'https://yt.example/140');
      expect(best.sizeBytes, 1370 + 7);
      expect(best.format, 'mp4');
      expect(best.needsRendering, isTrue);
      expect(best.isSlideshow, isFalse);
    });

    test('keeps the higher bitrate of two streams at one quality', () {
      final options = YouTubeExtractor.planMergedOptions(
        videos: [
          _stream(298, '720p60', 720, bitrate: 3000),
          _stream(136, '720p', 720, bitrate: 1000),
          _stream(398, '720p60', 720, bitrate: 2000),
        ],
        audio: audio,
        aboveHeight: 360,
      );

      expect(options.map((o) => o.id), ['yt_merged_298', 'yt_merged_136']);
    });

    // Unlike a slideshow, a merged option is the post's own video at a real
    // resolution, so "Highest" must land on it.
    test('a merged option wins the default selection', () {
      const muxed = VideoQualityOption.video(
        id: 'yt_muxed_18',
        label: VideoWithAudio('360p'),
        quality: '360p',
        format: 'mp4',
        downloadUrl: 'https://yt.example/18',
      );
      final metadata = _metadata([_merged(), muxed]);

      expect(
        QualityHelper.bestMatch(metadata.qualities, 'Highest')!.id,
        'yt_merged_137',
      );
      expect(
        QualityHelper.bestMatch(metadata.qualities, '360p')!.id,
        'yt_muxed_18',
      );
      expect(metadata.bestQuality!.id, 'yt_merged_137');
    });
  });

  group('fetching a stream in ranges', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('stream_fetch'));
    tearDown(() => root.deleteSync(recursive: true));

    final body = List<int>.generate(25, (index) => index);

    MockClient rangedServer(List<String> ranges) => MockClient((request) async {
      final range = request.headers['Range']!;
      ranges.add(range);
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!).clamp(0, body.length - 1);
      return http.Response.bytes(
        body.sublist(start, end + 1),
        206,
        headers: {'content-range': 'bytes $start-$end/${body.length}'},
      );
    });

    test('joins every range into the whole file', () async {
      final ranges = <String>[];
      final reported = <int>[];
      final file = File('${root.path}/out');

      await fetchStreamToFile(
        'https://yt.example/v',
        file,
        client: rangedServer(ranges),
        chunkBytes: 10,
        onBytes: reported.add,
      );

      expect(file.readAsBytesSync(), body);
      expect(ranges, ['bytes=0-9', 'bytes=10-19', 'bytes=20-29']);
      expect(reported.last, 25);
    });

    test('reads a server that ignores the range to the end', () async {
      final file = File('${root.path}/out');
      var requests = 0;

      await fetchStreamToFile(
        'https://yt.example/v',
        file,
        client: MockClient((_) async {
          requests++;
          return http.Response.bytes(body, 200);
        }),
        chunkBytes: 10,
      );

      expect(file.readAsBytesSync(), body);
      expect(requests, 1);
    });

    test('retries a server error and gives up on a refusal', () async {
      var calls = 0;
      await fetchStreamToFile(
        'https://yt.example/v',
        File('${root.path}/retried'),
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? http.Response('busy', 503)
              : http.Response.bytes(body, 200);
        }),
      );
      expect(calls, 2);

      await expectLater(
        fetchStreamToFile(
          'https://yt.example/v',
          File('${root.path}/refused'),
          client: MockClient((_) async => http.Response('no', 403)),
        ),
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.fetchFailed,
          ),
        ),
      );
    });

    test('stops between ranges once cancelled', () async {
      final ranges = <String>[];
      await expectLater(
        fetchStreamToFile(
          'https://yt.example/v',
          File('${root.path}/out'),
          client: rangedServer(ranges),
          chunkBytes: 10,
          isCancelled: () => ranges.isNotEmpty,
        ),
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.cancelled,
          ),
        ),
      );
      expect(ranges, hasLength(1));
    });

    test('probes the real length from the first byte', () async {
      final ranges = <String>[];
      expect(
        await probeStreamLength(
          'https://yt.example/v',
          client: rangedServer(ranges),
        ),
        body.length,
      );
      expect(ranges, ['bytes=0-0']);
    });

    test('a probe that finds no length fails the fetch', () async {
      await expectLater(
        probeStreamLength(
          'https://yt.example/v',
          client: MockClient((_) async => http.Response('', 403)),
        ),
        throwsA(
          isA<SlideshowException>().having(
            (e) => e.kind,
            'kind',
            SlideshowFailureKind.fetchFailed,
          ),
        ),
      );
    });
  });

  group('downloading a merged option', () {
    late Directory root;
    late Directory workspace;
    late MemoryStorage storage;

    setUp(() {
      root = Directory.systemTemp.createTempSync('merged_download');
      final downloads = Directory('${root.path}/downloads')..createSync();
      workspace = Directory('${root.path}/work')..createSync();
      storage = MemoryStorage(downloads);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    DownloadProvider provider(
      SlideshowRenderer renderer,
      _FakeFetcher fetcher, {
      ExtractorRegistry? registry,
    }) => DownloadProvider(
      downloadService: InertDownloadService(),
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      extractorRegistry: registry,
      slideshowRenderer: renderer,
      streamFetcher: fetcher.call,
      slideshowWorkspace: () async => Directory(
        '${workspace.path}/${DateTime.now().microsecondsSinceEpoch}',
      )..createSync(recursive: true),
    );

    const noGallery = DownloadOptions(autoSaveToGallery: false);

    test('fetches both streams and joins them into one file', () async {
      final muxer = _FakeMuxer();
      final fetcher = _FakeFetcher({
        'https://yt.example/video-1080': [1, 2, 3],
        'https://yt.example/audio': [4, 5],
      });
      final downloader = provider(muxer, fetcher);
      final option = _merged();

      final queued = await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      // Nothing entered the URL queue: there is no single URL to fetch.
      expect(queued, isEmpty);

      await _waitUntil(() => downloader.allTasks.any((t) => t.isDone));
      final task = downloader.allTasks.single;
      expect(task.status, DownloadStatus.completed);
      expect(task.progress, 1);
      expect(task.sourceOptionId, 'yt_merged_137');
      expect(File(task.filePath!).readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(task.totalBytes, 5);
      expect(fetcher.fetched, [
        'https://yt.example/video-1080',
        'https://yt.example/audio',
      ]);
      // The two stream files are scratch; only the joined one is kept.
      expect(workspace.listSync(recursive: true).whereType<File>(), isEmpty);
      expect(storage.receipts.map((r) => r['id']), [task.id]);
    });

    test('a failed fetch fails the task and never muxes', () async {
      final muxer = _FakeMuxer();
      final downloader = provider(
        muxer,
        _FakeFetcher({
          'https://yt.example/video-1080': [1],
        }),
      );
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => downloader.allTasks.any((t) => t.isDone));

      final task = downloader.allTasks.single;
      expect(task.status, DownloadStatus.failed);
      expect(task.errorMessage, l10n.downloadFailed);
      expect(task.filePath, isNull);
      expect(muxer.calls, isEmpty);
    });

    test('a cancel during the fetch leaves no file behind', () async {
      final muxer = _FakeMuxer();
      final downloader = provider(
        muxer,
        _FakeFetcher(
          {
            'https://yt.example/audio': [4],
          },
          blocking: {'https://yt.example/video-1080'},
        ),
      );
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => downloader.allTasks.isNotEmpty);
      final task = downloader.allTasks.single;
      downloader.cancelTask(task.id);
      await _waitUntil(() => muxer.cancelledIds.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(task.status, DownloadStatus.cancelled);
      expect(task.errorMessage, isNull);
      expect(muxer.calls, isEmpty);
      expect(storage.downloadDir.listSync(), isEmpty);
    });

    // A URL download already refuses a second copy of an option that is still
    // in flight; a rendered one was split off before that check and was
    // fetched and muxed twice.
    test('the same merged option is not started twice while running', () async {
      final muxer = _FakeMuxer();
      final fetcher = _FakeFetcher(
        {
          'https://yt.example/audio': [4],
        },
        blocking: {'https://yt.example/video-1080'},
      );
      final downloader = provider(muxer, fetcher);
      final option = _merged();
      final metadata = _metadata([option]);

      await downloader.startNewDownloads(
        metadata: metadata,
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => fetcher.fetched.isNotEmpty);
      await downloader.startNewDownloads(
        metadata: metadata,
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(downloader.allTasks, hasLength(1));
      expect(fetcher.fetched, hasLength(1));
      downloader.cancelTask(downloader.allTasks.single.id);
    });

    // Stream URLs are signed and expire within hours, so a retry must not
    // reuse the remembered ones while the post can still be re-read.
    test('a retry re-extracts fresh stream urls', () async {
      final muxer = _FakeMuxer();
      final fresh = _merged(
        video: 'https://yt.example/video-fresh',
        audio: 'https://yt.example/audio-fresh',
      );
      final registry = _FixedRegistry(_metadata([fresh]));
      final fetcher = _FakeFetcher({
        'https://yt.example/video-fresh': [7],
        'https://yt.example/audio-fresh': [8],
      });
      final downloader = provider(muxer, fetcher, registry: registry);
      final stale = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([stale]),
        qualities: [stale],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => downloader.allTasks.any((t) => t.isDone));
      final task = downloader.allTasks.single;
      expect(task.status, DownloadStatus.failed);

      await downloader.retryTask(task, l10n: l10n, options: noGallery);
      await _waitUntil(() => task.status == DownloadStatus.completed);

      expect(registry.calls, 1);
      expect(task.status, DownloadStatus.completed);
      expect(File(task.filePath!).readAsBytesSync(), [7, 8]);
    });

    test('a muxer failure reports a render failure', () async {
      final downloader = provider(
        _FakeMuxer(failWith: SlideshowFailureKind.outOfSpace),
        _FakeFetcher({
          'https://yt.example/video-1080': [1],
          'https://yt.example/audio': [2],
        }),
      );
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => downloader.allTasks.any((t) => t.isDone));

      final task = downloader.allTasks.single;
      expect(task.status, DownloadStatus.failed);
      expect(task.errorMessage, l10n.slideshowOutOfSpace);
    });
  });

  group('merging through background transfers', () {
    late Directory root;
    late Directory streams;
    late MemoryStorage storage;

    setUp(() {
      root = Directory.systemTemp.createTempSync('background_merge');
      final downloads = Directory('${root.path}/downloads')..createSync();
      streams = Directory('${root.path}/streams')..createSync();
      storage = MemoryStorage(downloads);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    DownloadProvider provider(
      SlideshowRenderer renderer,
      _PairGateway gateway, {
      _FakeFetcher? fetcher,
    }) => DownloadProvider(
      downloadService: gateway,
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      slideshowRenderer: renderer,
      streamFetcher: (fetcher ?? _FakeFetcher({})).call,
      slideshowWorkspace: () async =>
          Directory('${root.path}/work')..createSync(recursive: true),
    );

    const noGallery = DownloadOptions(autoSaveToGallery: false);

    StreamPairFiles writeStreams(List<int> video, List<int> audio) {
      final videoFile = File('${streams.path}/video.mp4')
        ..writeAsBytesSync(video);
      final audioFile = File('${streams.path}/audio.m4a')
        ..writeAsBytesSync(audio);
      return (videoPath: videoFile.path, audioPath: audioFile.path);
    }

    test('hands the fetch to the gateway and joins what it fetched', () async {
      final muxer = _FakeMuxer();
      final gateway = _PairGateway();
      final fetcher = _FakeFetcher({});
      final downloader = provider(muxer, gateway, fetcher: fetcher);
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => gateway.started.isNotEmpty);
      final transfer = gateway.started.single;
      final task = downloader.allTasks.single;
      expect(transfer.taskId, task.id);
      expect(transfer.source.videoUrl, 'https://yt.example/video-1080');
      expect(transfer.autoSaveToGallery, isFalse);

      transfer.report(50, 2048);
      expect(task.progress, closeTo(0.475, 1e-9));
      expect(task.receivedBytes, 50);
      expect(task.totalBytes, 100);
      expect(task.downloadSpeed, 2048);

      transfer.complete(writeStreams([1, 2, 3], [4, 5]));
      await _waitUntil(() => task.isDone);

      expect(task.status, DownloadStatus.completed);
      expect(File(task.filePath!).readAsBytesSync(), [1, 2, 3, 4, 5]);
      expect(task.downloadSpeed, 0);
      expect(transfer.discarded, isTrue);
      expect(fetcher.fetched, isEmpty, reason: 'nothing fetched in Dart');
    });

    test('the task is in history before its parts start', () async {
      final gateway = _PairGateway();
      final downloader = provider(_FakeMuxer(), gateway);
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => gateway.started.isNotEmpty);

      // A process ended now must find the task on the next launch, or the
      // parts arriving without the app are thrown away.
      expect(storage.history.map((t) => t['id']), [
        gateway.started.single.taskId,
      ]);
      expect(storage.history.single['status'], isNot('completed'));
    });

    test('a cancel stops the transfer and never muxes', () async {
      final muxer = _FakeMuxer();
      final gateway = _PairGateway();
      final downloader = provider(muxer, gateway);
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => gateway.started.isNotEmpty);
      final task = downloader.allTasks.single;

      downloader.cancelTask(task.id);
      await _waitUntil(() => gateway.started.single.discarded);

      expect(gateway.cancelled, [task.id]);
      expect(task.status, DownloadStatus.cancelled);
      expect(task.errorMessage, isNull);
      expect(muxer.calls, isEmpty);
    });

    test('a failed transfer fails the task', () async {
      final gateway = _PairGateway();
      final downloader = provider(_FakeMuxer(), gateway);
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => gateway.started.isNotEmpty);
      gateway.started.single.fail(
        const SlideshowException(SlideshowFailureKind.fetchFailed),
      );
      final task = downloader.allTasks.single;
      await _waitUntil(() => task.isDone);

      expect(task.status, DownloadStatus.failed);
      expect(task.errorMessage, l10n.downloadFailed);
    });

    test('deleting a running merge stops its transfer', () async {
      final gateway = _PairGateway();
      final downloader = provider(_FakeMuxer(), gateway);
      final option = _merged();

      await downloader.startNewDownloads(
        metadata: _metadata([option]),
        qualities: [option],
        l10n: l10n,
        options: noGallery,
      );
      await _waitUntil(() => gateway.started.isNotEmpty);
      final task = downloader.allTasks.single;

      await downloader.deleteTask(task.id);
      await _waitUntil(() => gateway.started.single.discarded);

      expect(gateway.cancelled, [task.id]);
      expect(downloader.allTasks, isEmpty);
    });

    test('finishes a merge the previous process left fetching', () async {
      final interrupted = DownloadTask(
        id: 'merge-1',
        videoId: 'dQw4w9WgXcQ',
        title: 'A video',
        author: 'Author',
        thumbnailUrl: '',
        downloadUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        originalUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        platform: VideoPlatform.youtube,
        qualityLabel: '1080p',
        format: 'mp4',
        status: DownloadStatus.downloading,
      );
      final gone = DownloadTask(
        id: 'merge-2',
        videoId: 'other',
        title: 'Finished earlier',
        author: 'Author',
        thumbnailUrl: '',
        originalUrl: 'https://www.youtube.com/watch?v=other',
        downloadUrl: 'https://www.youtube.com/watch?v=other',
        platform: VideoPlatform.youtube,
        qualityLabel: '1080p',
        format: 'mp4',
        status: DownloadStatus.completed,
      );
      storage.history = [interrupted.toJson(), gone.toJson()];
      final gateway = _PairGateway()
        ..recovered.addAll([
          _FakeTransfer('merge-1', autoSaveToGallery: false),
          _FakeTransfer('merge-2', autoSaveToGallery: false),
          _FakeTransfer('merge-3', autoSaveToGallery: false),
        ]);
      final resumed = gateway.recovered.first;
      final downloader = provider(_FakeMuxer(), gateway);

      await _waitUntil(() => downloader.allTasks.length == 2);
      final task = downloader.allTasks.firstWhere((t) => t.id == 'merge-1');
      expect(task.status, DownloadStatus.downloading);
      expect(task.errorMessage, isNull);
      // Neither a finished task nor one no longer in history is resumed.
      expect(gateway.recovered[1].discarded, isTrue);
      expect(gateway.recovered[2].discarded, isTrue);

      resumed.complete(writeStreams([9, 8], [7]));
      await _waitUntil(() => task.isDone);

      expect(task.status, DownloadStatus.completed);
      expect(File(task.filePath!).readAsBytesSync(), [9, 8, 7]);
      expect(resumed.discarded, isTrue);
      expect(storage.receipts.map((r) => r['id']), contains('merge-1'));
    });
  });
}

/// A [StreamPairGateway] whose transfers the test finishes by hand.
class _PairGateway extends InertDownloadService implements StreamPairGateway {
  final List<_FakeTransfer> started = [];
  final List<_FakeTransfer> recovered = [];
  final List<String> cancelled = [];

  @override
  Future<StreamPairTransfer> startStreamPair({
    required String taskId,
    required String title,
    required MergeSource source,
    required bool autoSaveToGallery,
  }) async {
    final transfer = _FakeTransfer(
      taskId,
      source: source,
      autoSaveToGallery: autoSaveToGallery,
    );
    started.add(transfer);
    return transfer;
  }

  @override
  List<StreamPairTransfer> takeRecoveredStreamPairs() => List.of(recovered);

  @override
  void cancelStreamPair(String taskId) {
    cancelled.add(taskId);
    for (final transfer in [...started, ...recovered]) {
      if (transfer.taskId == taskId) {
        transfer.fail(const SlideshowException(SlideshowFailureKind.cancelled));
      }
    }
  }
}

class _FakeTransfer implements StreamPairTransfer {
  _FakeTransfer(
    this.taskId, {
    this.source = const MergeSource(videoUrl: '', audioUrl: ''),
    required this.autoSaveToGallery,
  }) {
    _files.future.ignore();
  }

  @override
  final String taskId;
  final MergeSource source;
  @override
  final bool autoSaveToGallery;
  final Completer<StreamPairFiles> _files = Completer<StreamPairFiles>();
  void Function(int receivedBytes, double bytesPerSecond)? _onProgress;
  bool discarded = false;

  @override
  int get totalBytes => 100;

  @override
  Future<StreamPairFiles> get files => _files.future;

  @override
  set onProgress(void Function(int receivedBytes, double bytesPerSecond)? cb) =>
      _onProgress = cb;

  void report(int received, double speed) => _onProgress?.call(received, speed);

  void complete(StreamPairFiles files) => _files.complete(files);

  void fail(SlideshowException error) {
    if (!_files.isCompleted) _files.completeError(error);
  }

  @override
  Future<void> discard() async {
    fail(const SlideshowException(SlideshowFailureKind.cancelled));
    discarded = true;
  }
}
