import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';

import 'support/inert_download_service.dart';
import 'support/memory_storage.dart';

/// Stands in for the platform muxer: records the files it was asked to join
/// and writes a marker where the MP4 would go.
class _FakeMuxer implements SlideshowRenderer {
  _FakeMuxer({this.failWith});

  final SlideshowFailureKind? failWith;
  final List<({String video, String audio, bool audioOptional})> calls = [];
  final Map<String, String> contents = {};

  @override
  bool get isSupported => true;

  @override
  Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    String? renderId,
    bool audioOptional = false,
    void Function(double progress)? onProgress,
  }) async {
    calls.add((
      video: videoPath,
      audio: audioPath,
      audioOptional: audioOptional,
    ));
    for (final path in {videoPath, audioPath}) {
      contents[path] = File(path).readAsStringSync();
    }
    final failure = failWith;
    if (failure != null) throw SlideshowException(failure);
    await File(outputPath).writeAsString('mp4');
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
  Future<void> cancel(String renderId) async {}
}

/// Writes each playlist's table entry where its segments would be joined.
class _FakeStreams {
  _FakeStreams(this.bodies, {this.failWith});

  final Map<String, String> bodies;
  final SlideshowFailureKind? failWith;
  final List<String> fetched = [];

  Future<void> call(
    String playlistUrl,
    File into, {
    void Function(double fraction, int receivedBytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    fetched.add(playlistUrl);
    final failure = failWith;
    if (failure != null) throw SlideshowException(failure);
    final body = bodies[playlistUrl]!;
    await into.writeAsString(body);
    onProgress?.call(1, body.length);
  }
}

VideoMetadata _metadata(StreamSource source) => VideoMetadata(
  id: 'clip',
  originalUrl: 'https://video.example/watch/42',
  title: 'A clip',
  author: 'video.example',
  coverUrl: '',
  platform: VideoPlatform.generic,
  qualities: [
    VideoQualityOption.stream(
      id: 'gen_hls_720',
      label: const VideoWithAudio('720p'),
      quality: '720p',
      source: source,
    ),
  ],
);

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  const noGallery = DownloadOptions(autoSaveToGallery: false);
  const video = 'https://cdn.example/720/index.m3u8';
  const audio = 'https://cdn.example/audio/en.m3u8';

  late Directory root;
  late MemoryStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('stream_download');
    storage = MemoryStorage(Directory('${root.path}/downloads')..createSync());
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DownloadProvider provider(
    SlideshowRenderer renderer,
    _FakeStreams streams, {
    DashFetcher? dashFetcher,
  }) => DownloadProvider(
    downloadService: InertDownloadService(),
    storageService: storage,
    historyRepository: storage,
    fileActions: storage,
    slideshowRenderer: renderer,
    hlsFetcher: streams.call,
    dashFetcher: dashFetcher,
    slideshowWorkspace: () async =>
        Directory('${root.path}/work')..createSync(recursive: true),
  );

  Future<DownloadTask> download(
    DownloadProvider downloads,
    StreamSource source,
  ) async {
    final metadata = _metadata(source);
    await downloads.startNewDownloads(
      metadata: metadata,
      qualities: metadata.qualities,
      l10n: l10n,
      options: noGallery,
    );
    await _waitUntil(
      () =>
          downloads.allTasks.isNotEmpty &&
          downloads.allTasks.single.status != DownloadStatus.downloading,
    );
    return downloads.allTasks.single;
  }

  test('segments holding picture and sound are one file read twice', () async {
    final muxer = _FakeMuxer();
    final streams = _FakeStreams({video: 'segments'});

    final task = await download(
      provider(muxer, streams),
      const HlsSource(videoPlaylistUrl: video),
    );

    expect(task.status, DownloadStatus.completed);
    expect(streams.fetched, [video]);
    expect(muxer.calls.single.video, muxer.calls.single.audio);
    // Such segments may be silent, which is not for the muxer to refuse.
    expect(muxer.calls.single.audioOptional, isTrue);
    expect(muxer.contents[muxer.calls.single.video], 'segments');
    expect(File(task.filePath!).readAsStringSync(), 'mp4');
    expect(task.filePath, endsWith('.mp4'));
    // The fetched segments are scratch; only the joined file is kept.
    expect(Directory('${root.path}/work').existsSync(), isFalse);
  });

  test('sound served apart is fetched and joined as a second file', () async {
    final muxer = _FakeMuxer();
    final streams = _FakeStreams({video: 'picture', audio: 'sound'});

    final task = await download(
      provider(muxer, streams),
      const HlsSource(videoPlaylistUrl: video, audioPlaylistUrl: audio),
    );

    expect(task.status, DownloadStatus.completed);
    expect(streams.fetched, [video, audio]);
    final call = muxer.calls.single;
    expect(muxer.contents[call.video], 'picture');
    expect(muxer.contents[call.audio], 'sound');
    // A playlist of its own promises sound; its absence is a failure.
    expect(call.audioOptional, isFalse);
  });

  test('a DASH stream is fetched by representation and joined', () async {
    final muxer = _FakeMuxer();
    final asked = <String>[];

    final task = await download(
      provider(
        muxer,
        _FakeStreams({}),
        dashFetcher:
            (
              manifestUrl,
              representationId,
              into, {
              onProgress,
              isCancelled,
            }) async {
              asked.add('$manifestUrl#$representationId');
              await into.writeAsString(representationId);
              onProgress?.call(1, representationId.length);
            },
      ),
      const DashSource(
        manifestUrl: 'https://cdn.example/film.mpd',
        videoId: 'v720',
        audioId: 'aac',
      ),
    );

    expect(task.status, DownloadStatus.completed);
    expect(asked, [
      'https://cdn.example/film.mpd#v720',
      'https://cdn.example/film.mpd#aac',
    ]);
    final call = muxer.calls.single;
    expect(muxer.contents[call.video], 'v720');
    expect(muxer.contents[call.audio], 'aac');
    expect(call.audioOptional, isFalse);
  });

  test('a DASH stream with no sound is joined as picture alone', () async {
    final muxer = _FakeMuxer();

    final task = await download(
      provider(
        muxer,
        _FakeStreams({}),
        dashFetcher:
            (manifestUrl, representationId, into, {onProgress, isCancelled}) =>
                into.writeAsString(representationId),
      ),
      const DashSource(
        manifestUrl: 'https://cdn.example/film.mpd',
        videoId: 'v720',
      ),
    );

    expect(task.status, DownloadStatus.completed);
    expect(muxer.calls.single.video, muxer.calls.single.audio);
    expect(muxer.calls.single.audioOptional, isTrue);
  });

  test('a stream that turns out live says so on the task', () async {
    final task = await download(
      provider(
        _FakeMuxer(),
        _FakeStreams({}, failWith: SlideshowFailureKind.streamLive),
      ),
      const HlsSource(videoPlaylistUrl: video),
    );

    expect(task.status, DownloadStatus.failed);
    expect(task.errorMessage, l10n.streamLive);
    expect(task.filePath, isNull);
  });

  test('segments the device cannot join are named as that', () async {
    final task = await download(
      provider(
        _FakeMuxer(failWith: SlideshowFailureKind.encodeFailed),
        _FakeStreams({video: 'segments'}),
      ),
      const HlsSource(videoPlaylistUrl: video),
    );

    expect(task.status, DownloadStatus.failed);
    expect(task.errorMessage, l10n.streamUnreadable);
  });
}
