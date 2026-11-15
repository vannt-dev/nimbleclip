import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/stream_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/audio/audio_converter.dart';
import 'package:nimble_clip/services/download_service.dart';
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
    final file = File('${directory.path}/${task.id}.${task.format}');
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

/// Storage whose shared library is a list: what was saved to it, as what, and
/// what was asked of it afterwards.
class _LibraryStorage extends MemoryStorage {
  _LibraryStorage(super.downloadDir);

  final List<({String path, bool isAudio, bool isImage, bool existed})> saved =
      [];
  final List<({String path, bool isAudio})> existenceChecks = [];
  bool accepts = true;
  bool? stillInLibrary = true;

  /// The address the library hands back for a saved file, or none at all.
  String? uri = 'content://media/external/audio/media/7';

  @override
  Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async {
    saved.add((
      path: filePath,
      isAudio: isAudio,
      isImage: isImage,
      existed: File(filePath).existsSync(),
    ));
    return accepts;
  }

  @override
  Future<String?> galleryUri(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) async => uri;

  @override
  Future<bool?> galleryExists(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) async {
    existenceChecks.add((path: filePath, isAudio: isAudio));
    return stillInLibrary;
  }
}

/// Writes a small MP3 stand-in, or waits to be released first.
class _FakeConverter implements AudioConverter {
  final List<String> sources = [];
  final List<String> cancelled = [];
  Completer<void>? gate;

  @override
  bool get isSupported => true;

  @override
  Future<String> toMp3({
    required String sourcePath,
    required String outputPath,
    required String jobId,
    void Function(double progress)? onProgress,
  }) async {
    sources.add(sourcePath);
    await gate?.future;
    if (cancelled.contains(jobId)) {
      throw const AudioConversionException(
        AudioConversionFailureKind.cancelled,
      );
    }
    await File(outputPath).writeAsBytes(List.filled(20, 2));
    return outputPath;
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    gate?.complete();
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

VideoMetadata _post({bool audio = true, String format = 'm4a'}) =>
    VideoMetadata(
      id: 'post',
      originalUrl: 'https://example.com/post',
      title: 'Song',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        if (audio)
          VideoQualityOption.audio(
            id: 'audio',
            label: const AudioM4a(128),
            quality: 'Audio',
            format: format,
            downloadUrl: 'https://cdn.example.com/a.$format',
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
  title: 'A clip',
  author: 'video.example',
  coverUrl: '',
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

/// Time for a save that should not happen to show itself.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late Directory root;
  late _LibraryStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nimbleclip_music_library');
    storage = _LibraryStorage(
      Directory('${root.path}/downloads')..createSync(),
    );
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DownloadProvider provider({AudioConverter? converter, bool toMp3 = false}) =>
      DownloadProvider(
        downloadService: _FileDownloadService(storage.downloadDir),
        storageService: storage,
        historyRepository: storage,
        fileActions: storage,
        audioConverter: converter,
        slideshowRenderer: _FakeMuxer(),
        hlsFetcher: (url, into, {onProgress, isCancelled}) =>
            into.writeAsString('sound'),
        slideshowWorkspace: () async =>
            Directory('${root.path}/work')..createSync(recursive: true),
      )..convertAudioToMp3 = toMp3;

  Future<DownloadTask> start(
    DownloadProvider downloads, {
    VideoMetadata? metadata,
    DownloadOptions options = const DownloadOptions(),
  }) async {
    final post = metadata ?? _post();
    await downloads.startNewDownloads(
      metadata: post,
      qualities: post.qualities,
      l10n: l10n,
      options: options,
    );
    return downloads.allTasks.single;
  }

  test('a finished audio download is added to the Music library', () async {
    final task = await start(provider());
    await _until(() => task.isSavedToGallery);

    expect(task.status, DownloadStatus.completed);
    expect(storage.saved, hasLength(1));
    expect(storage.saved.single.path, task.filePath);
    expect(storage.saved.single.isAudio, isTrue);
    expect(storage.saved.single.isImage, isFalse);
    expect(task.isSavedToGallery, isTrue);
    expect(task.galleryUri, storage.uri);
    // The app keeps its own copy unless asked to remove it.
    expect(File(task.filePath!).existsSync(), isTrue);
    expect(storage.receipts.single['id'], task.id);
  });

  test('nothing is added when automatic saving is off', () async {
    final task = await start(
      provider(),
      options: const DownloadOptions(autoSaveToGallery: false),
    );
    await _until(() => task.status == DownloadStatus.completed);
    await _settle();

    expect(storage.saved, isEmpty);
    expect(task.isSavedToGallery, isFalse);
    expect(task.galleryUri, isNull);
  });

  test('a converted download reaches the library as the MP3', () async {
    final converter = _FakeConverter()..gate = Completer<void>();
    final task = await start(provider(converter: converter, toMp3: true));
    await _until(() => converter.sources.isNotEmpty);

    // Still converting: the fetched file must not be what gets saved.
    expect(storage.saved, isEmpty);

    converter.gate!.complete();
    await _until(() => task.isSavedToGallery);

    expect(task.format, 'mp3');
    expect(storage.saved, hasLength(1));
    expect(storage.saved.single.path, endsWith('.mp3'));
    expect(storage.saved.single.path, task.filePath);
    expect(storage.saved.single.existed, isTrue);
    expect(storage.saved.single.isAudio, isTrue);
  });

  test('a download cancelled while converting is not added', () async {
    final converter = _FakeConverter()..gate = Completer<void>();
    final downloads = provider(converter: converter, toMp3: true);
    final task = await start(downloads);
    await _until(() => converter.sources.isNotEmpty);

    downloads.cancelTask(task.id);
    await _until(() => task.filePath == null);
    await _settle();

    expect(task.status, DownloadStatus.cancelled);
    expect(storage.saved, isEmpty);
    expect(task.isSavedToGallery, isFalse);
  });

  test('sound joined from a stream is added once, after conversion', () async {
    final converter = _FakeConverter();
    final task = await start(
      provider(converter: converter, toMp3: true),
      metadata: _streamedSound(),
    );
    await _until(() => task.isSavedToGallery);

    expect(task.status, DownloadStatus.completed);
    expect(converter.sources, hasLength(1));
    expect(storage.saved, hasLength(1));
    expect(storage.saved.single.path, endsWith('.mp3'));
    expect(storage.saved.single.isAudio, isTrue);
    expect(task.galleryUri, storage.uri);
  });

  test('a library that refuses the file leaves the download whole', () async {
    storage.accepts = false;
    final task = await start(provider());
    await _until(() => storage.saved.isNotEmpty);
    await _settle();

    expect(task.status, DownloadStatus.completed);
    expect(task.isSavedToGallery, isFalse);
    expect(task.galleryUri, isNull);
    expect(File(task.filePath!).existsSync(), isTrue);
  });

  group('removing the local copy after saving', () {
    const removing = DownloadOptions(removeCacheAfterGallery: true);

    test(
      'removes it once the library has given the track an address',
      () async {
        final task = await start(provider(), options: removing);
        await _until(() => task.isSavedToGallery && task.filePath == null);

        final saved = storage.saved.single.path;
        expect(task.filePath, isNull);
        expect(File(saved).existsSync(), isFalse);
        expect(task.galleryUri, storage.uri);
        expect(task.status, DownloadStatus.completed);
      },
    );

    test('keeps it when the library gave no address to open it by', () async {
      storage.uri = null;
      final task = await start(provider(), options: removing);
      await _until(() => task.isSavedToGallery);
      await _settle();

      expect(task.filePath, isNotNull);
      expect(File(task.filePath!).existsSync(), isTrue);
    });
  });

  test(
    'Save adds an audio download that was not saved automatically',
    () async {
      final downloads = provider();
      final task = await start(
        downloads,
        options: const DownloadOptions(autoSaveToGallery: false),
      );
      await _until(() => task.status == DownloadStatus.completed);

      expect(await downloads.saveToGalleryManually(task), isTrue);

      expect(storage.saved.single.isAudio, isTrue);
      expect(task.isSavedToGallery, isTrue);
      expect(task.galleryUri, storage.uri);
    },
  );

  test('a video is still saved by the download itself, not twice', () async {
    final task = await start(provider(), metadata: _post(audio: false));
    await _until(() => task.status == DownloadStatus.completed);
    await _settle();

    // The stand-in download service saves nothing, and the provider must not
    // step in for a video the way it does for audio.
    expect(storage.saved, isEmpty);
  });

  test(
    'a saved track whose local copy is gone is looked up as audio and kept',
    () async {
      final downloads = provider();
      final task = await start(downloads);
      await _until(() => task.isSavedToGallery);
      File(task.filePath!).deleteSync();
      final missing = task.filePath!;

      expect(await downloads.ensureLocalFileAvailable(task), isFalse);

      expect(storage.existenceChecks.last, (path: missing, isAudio: true));
      expect(task.isSavedToGallery, isTrue);
      expect(storage.receipts.single['id'], task.id);
    },
  );

  test('a saved track gone from the library too loses its receipt', () async {
    final downloads = provider();
    final task = await start(downloads);
    await _until(() => task.isSavedToGallery);
    File(task.filePath!).deleteSync();
    storage.stillInLibrary = false;

    expect(await downloads.ensureLocalFileAvailable(task), isFalse);

    expect(task.isSavedToGallery, isFalse);
    expect(storage.receipts, isEmpty);
  });
}
