import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/lyrics/lrclib_client.dart';
import 'package:nimble_clip/services/lyrics/lyrics_file.dart';
import 'package:nimble_clip/services/lyrics/lyrics_query.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';

import 'support/inert_download_service.dart';
import 'support/memory_storage.dart';

/// Finishes every download at once, leaving a real file of the task's format.
class _FileDownloadService extends InertDownloadService {
  _FileDownloadService(this.directory);

  final Directory directory;

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    final file = File('${directory.path}/youtube_${task.id}.${task.format}');
    await file.writeAsBytes(List.filled(64, 1));
    task
      ..filePath = file.path
      ..status = DownloadStatus.completed
      ..progress = 1
      ..totalBytes = 64
      ..receivedBytes = 64
      ..completedAt = DateTime.now();
    onComplete(task, file.path);
  }
}

/// Answers every lookup with [answer], and remembers what was asked.
class _FakeLyrics implements LyricsSource {
  _FakeLyrics(this.answer);

  final Lyrics? answer;
  final List<LyricsQuery> queries = [];

  @override
  Future<Lyrics?> find(LyricsQuery query) async {
    queries.add(query);
    return answer;
  }
}

/// Storage with a Music library that takes audio and, unless told not to,
/// lyrics files.
class _LibraryStorage extends MemoryStorage {
  _LibraryStorage(super.downloadDir);

  static const audioUri = 'content://media/external/audio/media/7';
  final List<({String path, String audioUri, String text})> lyricsSaved = [];
  bool acceptsLyrics = true;

  @override
  Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async => true;

  @override
  Future<String?> galleryUri(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) async => audioUri;

  @override
  Future<bool> saveLyricsToLibrary(
    String lyricsPath, {
    required String audioUri,
  }) async {
    lyricsSaved.add((
      path: lyricsPath,
      audioUri: audioUri,
      text: File(lyricsPath).readAsStringSync(),
    ));
    return acceptsLyrics;
  }
}

/// Stands in for the platform muxer: writes a marker where the track goes.
class _FakeMuxer implements SlideshowRenderer {
  @override
  bool get isSupported => true;

  @override
  Future<bool> canMergeStreams() async => true;

  @override
  Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    String? renderId,
    bool audioOptional = false,
    bool audioOnly = false,
    void Function(double progress)? onProgress,
  }) async {
    await File(outputPath).writeAsString('m4a');
    return outputPath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _synced = Lyrics(text: '[00:01.00] First line', synced: true);
const _plain = Lyrics(text: 'First line', synced: false);

VideoMetadata _track({bool audio = true}) => VideoMetadata(
  id: 'track',
  originalUrl: 'https://example.com/track',
  title: 'Artist - Song (Official Audio)',
  author: 'ArtistVEVO',
  coverUrl: '',
  duration: const Duration(seconds: 233),
  platform: VideoPlatform.youtube,
  qualities: [
    if (audio)
      VideoQualityOption.audio(
        id: 'audio',
        label: const AudioM4a(128),
        quality: 'Audio',
        format: 'm4a',
        downloadUrl: 'https://cdn.example.com/a.m4a',
      )
    else
      VideoQualityOption(
        id: 'video',
        label: const VideoWithAudio('720p'),
        quality: '720p',
        format: 'mp4',
        downloadUrl: 'https://cdn.example.com/v.mp4',
      ),
  ],
);

VideoMetadata _streamedSound() => VideoMetadata(
  id: 'clip',
  originalUrl: 'https://video.example/watch/42',
  title: 'Song',
  author: 'Artist',
  coverUrl: '',
  duration: const Duration(seconds: 200),
  platform: VideoPlatform.generic,
  qualities: [
    VideoQualityOption.stream(
      id: 'stream_audio',
      label: const OriginalAudio(),
      quality: 'Audio AAC',
      format: 'm4a',
      kind: MediaKind.audio,
      source: const HlsSource(
        videoPlaylistUrl: 'https://cdn.example/audio/en.m3u8',
      ),
    ),
  ],
);

/// Waits for [done] to hold: the downloads here write real files, which on a
/// busy machine takes longer than any short fixed pause.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late Directory root;
  late _LibraryStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nimbleclip_lyrics');
    storage = _LibraryStorage(
      Directory('${root.path}/downloads')..createSync(),
    );
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DownloadProvider provider(LyricsSource lyrics, {bool saveLyrics = true}) =>
      DownloadProvider(
        downloadService: _FileDownloadService(storage.downloadDir),
        storageService: storage,
        historyRepository: storage,
        fileActions: storage,
        lyricsSource: lyrics,
        slideshowRenderer: _FakeMuxer(),
        hlsFetcher: (url, into, {onProgress, isCancelled}) =>
            into.writeAsString('sound'),
        slideshowWorkspace: () async =>
            Directory('${root.path}/work')..createSync(recursive: true),
      )..saveLyrics = saveLyrics;

  /// Starts [metadata]'s download and waits until it has been recorded as
  /// finished, which is after every step that follows the transfer.
  Future<DownloadTask> download(
    DownloadProvider downloads, {
    VideoMetadata? metadata,
    DownloadOptions options = const DownloadOptions(autoSaveToGallery: false),
  }) async {
    final post = metadata ?? _track();
    await downloads.startNewDownloads(
      metadata: post,
      qualities: post.qualities,
      l10n: l10n,
      options: options,
    );
    final task = downloads.allTasks.single;
    await _until(() => storage.receipts.any((r) => r['id'] == task.id));
    return task;
  }

  test('with the setting off, nothing is looked up or written', () async {
    final requests = <http.Request>[];
    final lrclib = LrclibClient(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 404);
      }),
      userAgent: () async => 'test',
    );
    final task = await download(provider(lrclib, saveLyrics: false));

    expect(task.status, DownloadStatus.completed);
    expect(requests, isEmpty);
    expect(File(lyricsPathFor(task.filePath!)).existsSync(), isFalse);
    expect(task.errorMessage, isNull);
  });

  test('synced lyrics are saved beside the audio file as .lrc', () async {
    final lyrics = _FakeLyrics(_synced);
    final task = await download(provider(lyrics));

    final audio = task.filePath!;
    final file = File(lyricsPathFor(audio));
    expect(file.path, audio.replaceFirst(RegExp(r'\.m4a$'), '.lrc'));
    expect(file.readAsStringSync(), '[00:01.00] First line\n');
    expect(task.status, DownloadStatus.completed);
    expect(task.errorMessage, l10n.lyricsSaved);

    final query = lyrics.queries.single;
    expect(query.artist, 'Artist');
    expect(query.track, 'Song');
    expect(query.duration, const Duration(seconds: 233));
  });

  test('plain lyrics are saved without timings and say so', () async {
    final task = await download(provider(_FakeLyrics(_plain)));

    expect(
      File(lyricsPathFor(task.filePath!)).readAsStringSync(),
      'First line\n',
    );
    expect(task.errorMessage, l10n.lyricsSavedPlain);
  });

  test('a track without lyrics is left as it was, silently', () async {
    final task = await download(provider(_FakeLyrics(null)));

    expect(task.status, DownloadStatus.completed);
    expect(File(lyricsPathFor(task.filePath!)).existsSync(), isFalse);
    expect(task.errorMessage, isNull);
  });

  test('a video download is not looked up', () async {
    final lyrics = _FakeLyrics(_synced);
    final task = await download(
      provider(lyrics),
      metadata: _track(audio: false),
    );

    expect(task.status, DownloadStatus.completed);
    expect(lyrics.queries, isEmpty);
  });

  test('sound joined from a stream gets its lyrics too', () async {
    final lyrics = _FakeLyrics(_synced);
    final downloads = provider(lyrics);
    final post = _streamedSound();
    await downloads.startNewDownloads(
      metadata: post,
      qualities: post.qualities,
      l10n: l10n,
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    final task = downloads.allTasks.single;
    await _until(() => task.status == DownloadStatus.completed);
    await _until(() => storage.receipts.any((r) => r['id'] == task.id));

    expect(lyrics.queries.single.duration, const Duration(seconds: 200));
    expect(File(lyricsPathFor(task.filePath!)).existsSync(), isTrue);
  });

  test('the lyrics follow the audio into the Music library', () async {
    final task = await download(
      provider(_FakeLyrics(_synced)),
      options: const DownloadOptions(removeCacheAfterGallery: true),
    );
    // Saving to the library records the task before its copy is removed.
    await _until(() => task.filePath == null);

    final saved = storage.lyricsSaved.single;
    expect(saved.audioUri, _LibraryStorage.audioUri);
    expect(saved.text, '[00:01.00] First line\n');
    // The app's own copies go together once the library holds both.
    expect(task.filePath, isNull);
    expect(File(saved.path).existsSync(), isFalse);
    expect(task.errorMessage, l10n.lyricsSaved);
  });

  test('lyrics the library refused are not reported as saved', () async {
    storage.acceptsLyrics = false;
    final task = await download(
      provider(_FakeLyrics(_synced)),
      options: const DownloadOptions(removeCacheAfterGallery: true),
    );
    // Saving to the library records the task before its copy is removed.
    await _until(() => task.filePath == null);

    expect(storage.lyricsSaved, hasLength(1));
    expect(task.filePath, isNull);
    expect(File(storage.lyricsSaved.single.path).existsSync(), isFalse);
    expect(task.errorMessage, isNull);
  });

  test('deleting the download deletes its lyrics file', () async {
    final downloads = provider(_FakeLyrics(_synced));
    final task = await download(downloads);
    final lyricsFile = File(lyricsPathFor(task.filePath!));
    expect(lyricsFile.existsSync(), isTrue);

    await downloads.deleteTask(task.id);

    expect(lyricsFile.existsSync(), isFalse);
  });

  group('lyricsPathFor', () {
    test('swaps the extension for .lrc', () {
      expect(
        lyricsPathFor('/music/NimbleClip/youtube_abc.m4a'),
        '/music/NimbleClip/youtube_abc.lrc',
      );
      expect(
        lyricsPathFor(r'C:\dl\soundcloud_x.mp3'),
        r'C:\dl\soundcloud_x.lrc',
      );
    });

    test('keeps dots that are part of the name', () {
      expect(lyricsPathFor('/dl/a.b.c.webm'), '/dl/a.b.c.lrc');
      expect(lyricsPathFor('/dl.d/track'), '/dl.d/track.lrc');
    });
  });
}
