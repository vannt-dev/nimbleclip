import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/merge_source.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/subtitle_file.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/extractors/registry.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:nimble_clip/services/subtitles/subtitles_file.dart';

import 'support/inert_download_service.dart';
import 'support/memory_storage.dart';

const _vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.500\nFirst line\n';
const _srt = '1\n00:00:01,000 --> 00:00:02,500\nFirst line\n\n';

/// Finishes every download at once, leaving a real file, and saves it to the
/// gallery when asked, as the system download does.
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
      ..isSavedToGallery = autoSaveToGallery
      ..progress = 1
      ..completedAt = DateTime.now();
    onComplete(task, file.path);
  }
}

/// Answers every subtitles lookup with [answer] and remembers what was asked.
class _CaptionedRegistry extends ExtractorRegistry {
  _CaptionedRegistry(this.answer);

  final SubtitleFile? answer;
  final List<({String url, String? languageCode})> asked = [];

  @override
  Future<SubtitleFile?> subtitlesFor(
    String rawUrl, {
    String? languageCode,
  }) async {
    asked.add((url: rawUrl, languageCode: languageCode));
    return answer;
  }
}

/// A gallery that takes videos and, unless told not to, subtitles files.
class _GalleryStorage extends MemoryStorage {
  _GalleryStorage(super.downloadDir);

  static const videoUri = 'content://media/external/video/media/9';
  final List<({String videoUri, String text})> subtitlesSaved = [];
  bool acceptsSubtitles = true;

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
  }) async => videoUri;

  @override
  Future<bool> saveSubtitlesToLibrary(
    String subtitlesPath, {
    required String videoUri,
  }) async {
    subtitlesSaved.add((
      videoUri: videoUri,
      text: File(subtitlesPath).readAsStringSync(),
    ));
    return acceptsSubtitles;
  }
}

/// Stands in for the platform muxer: writes a marker where the video goes.
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
    await File(outputPath).writeAsString('mp4');
    return outputPath;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

VideoMetadata _post(List<VideoQualityOption> qualities) => VideoMetadata(
  id: 'clip',
  originalUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
  title: 'A clip',
  author: 'Creator',
  coverUrl: '',
  platform: VideoPlatform.youtube,
  qualities: qualities,
);

const _video = VideoQualityOption(
  id: 'yt_muxed_18',
  label: VideoWithAudio('360p'),
  quality: '360p',
  format: 'mp4',
  downloadUrl: 'https://cdn.example.com/v.mp4',
);

const _audio = VideoQualityOption.audio(
  id: 'audio',
  label: AudioM4a(128),
  quality: 'Audio',
  format: 'm4a',
  downloadUrl: 'https://cdn.example.com/a.m4a',
);

const _merged = VideoQualityOption.merged(
  id: 'yt_merged_137',
  label: VideoWithAudio('1080p'),
  quality: '1080p',
  source: MergeSource(
    videoUrl: 'https://yt.example/video-1080',
    audioUrl: 'https://yt.example/audio',
    partBytes: 1 << 20,
  ),
);

/// Waits for [done] to hold: the downloads here write real files.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late Directory root;
  late _GalleryStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('nimbleclip_subtitles');
    storage = _GalleryStorage(
      Directory('${root.path}/downloads')..createSync(),
    );
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DownloadProvider provider(
    ExtractorRegistry registry, {
    bool saveSubtitles = true,
  }) => DownloadProvider(
    downloadService: _FileDownloadService(storage.downloadDir),
    storageService: storage,
    historyRepository: storage,
    fileActions: storage,
    extractorRegistry: registry,
    slideshowRenderer: _FakeMuxer(),
    streamFetcher: (url, into, {onBytes, isCancelled}) async {
      await into.writeAsBytes([1, 2, 3]);
      onBytes?.call(3);
    },
    slideshowWorkspace: () async =>
        Directory('${root.path}/work')..createSync(recursive: true),
  )..saveSubtitles = saveSubtitles;

  /// Starts [option]'s download and waits until it is recorded as finished,
  /// which is after every step that follows the transfer.
  Future<DownloadTask> download(
    DownloadProvider downloads, {
    VideoQualityOption option = _video,
    DownloadOptions options = const DownloadOptions(autoSaveToGallery: false),
  }) async {
    await downloads.startNewDownloads(
      metadata: _post([option]),
      qualities: [option],
      l10n: l10n,
      options: options,
    );
    await _until(() => downloads.allTasks.isNotEmpty);
    final task = downloads.allTasks.single;
    await _until(() => storage.receipts.any((r) => r['id'] == task.id));
    return task;
  }

  const subtitles = SubtitleFile(languageCode: 'en', webVtt: _vtt);

  test('with the setting off, nothing is asked or written', () async {
    final registry = _CaptionedRegistry(subtitles);
    final task = await download(provider(registry, saveSubtitles: false));

    expect(task.status, DownloadStatus.completed);
    expect(registry.asked, isEmpty);
    expect(File(subtitlesPathFor(task.filePath!)).existsSync(), isFalse);
    expect(task.errorMessage, isNull);
  });

  test('subtitles are saved beside the video as .srt', () async {
    final registry = _CaptionedRegistry(subtitles);
    final task = await download(provider(registry));

    final video = task.filePath!;
    final file = File(subtitlesPathFor(video));
    expect(file.path, video.replaceFirst(RegExp(r'\.mp4$'), '.srt'));
    expect(file.readAsStringSync(), _srt);
    expect(task.status, DownloadStatus.completed);
    expect(task.errorMessage, l10n.subtitlesSaved);
    // In the app's language, for the post the video came from.
    expect(registry.asked.single.url, _post(const []).originalUrl);
    expect(registry.asked.single.languageCode, 'en');
  });

  test('a video without subtitles is left as it was, silently', () async {
    final task = await download(provider(_CaptionedRegistry(null)));

    expect(task.status, DownloadStatus.completed);
    expect(File(subtitlesPathFor(task.filePath!)).existsSync(), isFalse);
    expect(task.errorMessage, isNull);
  });

  test('an audio download is not looked up', () async {
    final registry = _CaptionedRegistry(subtitles);
    final task = await download(provider(registry), option: _audio);

    expect(task.status, DownloadStatus.completed);
    expect(registry.asked, isEmpty);
  });

  test('a video joined on the device gets its subtitles too', () async {
    final registry = _CaptionedRegistry(subtitles);
    final task = await download(provider(registry), option: _merged);

    expect(task.status, DownloadStatus.completed);
    expect(File(subtitlesPathFor(task.filePath!)).readAsStringSync(), _srt);
  });

  test('the subtitles follow the video into the gallery', () async {
    final task = await download(
      provider(_CaptionedRegistry(subtitles)),
      options: const DownloadOptions(removeCacheAfterGallery: true),
    );
    await _until(() => task.filePath == null);

    final saved = storage.subtitlesSaved.single;
    expect(saved.videoUri, _GalleryStorage.videoUri);
    expect(saved.text, _srt);
    // The app's own copy went with the video's, and the note stays true.
    expect(storage.downloadDir.listSync(), isEmpty);
    expect(task.errorMessage, l10n.subtitlesSaved);
  });

  test('a joined video takes its subtitles into the gallery', () async {
    final task = await download(
      provider(_CaptionedRegistry(subtitles)),
      option: _merged,
      options: const DownloadOptions(),
    );

    expect(storage.subtitlesSaved.single.text, _srt);
    expect(task.errorMessage, l10n.subtitlesSaved);
  });

  test('a joined video leaves no app copy once in the gallery', () async {
    final task = await download(
      provider(_CaptionedRegistry(subtitles)),
      option: _merged,
      options: const DownloadOptions(removeCacheAfterGallery: true),
    );

    expect(task.status, DownloadStatus.completed);
    expect(task.isSavedToGallery, isTrue);
    expect(task.filePath, isNull);
    expect(storage.downloadDir.listSync(), isEmpty);
    expect(storage.subtitlesSaved.single.text, _srt);
    expect(task.errorMessage, l10n.subtitlesSaved);
  });

  test('subtitles the gallery refused are not claimed once gone', () async {
    storage.acceptsSubtitles = false;
    final task = await download(
      provider(_CaptionedRegistry(subtitles)),
      options: const DownloadOptions(removeCacheAfterGallery: true),
    );
    await _until(() => task.filePath == null);

    expect(storage.downloadDir.listSync(), isEmpty);
    expect(task.errorMessage, isNull);
  });

  test('deleting the download takes its subtitles with it', () async {
    final downloads = provider(_CaptionedRegistry(subtitles));
    final task = await download(downloads);
    final file = File(subtitlesPathFor(task.filePath!));
    expect(file.existsSync(), isTrue);

    await downloads.deleteTask(task.id);

    expect(file.existsSync(), isFalse);
  });
}
