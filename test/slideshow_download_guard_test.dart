import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer.dart';
import 'package:nimble_clip/services/storage_service.dart';

import 'support/inert_download_service.dart';

/// Stands in for the platform encoder, so the download flow can be exercised
/// without an emulator.
class _FakeRenderer implements SlideshowRenderer {
  _FakeRenderer({this.audioSkipped = false, this.failWith});

  @override
  bool get isSupported => true;

  final bool audioSkipped;
  final SlideshowFailureKind? failWith;

  int calls = 0;
  List<String>? lastImagePaths;
  String? lastAudioPath;
  Duration? lastPerImage;

  @override
  Future<SlideshowResult> render({
    required List<String> imagePaths,
    String? audioPath,
    required Duration perImage,
    required int width,
    required int height,
    required String outputPath,
  }) async {
    calls++;
    lastImagePaths = imagePaths;
    lastAudioPath = audioPath;
    lastPerImage = perImage;
    final failure = failWith;
    if (failure != null) throw SlideshowException(failure);
    await File(outputPath).writeAsBytes(const [0, 1, 2, 3]);
    return SlideshowResult(filePath: outputPath, audioSkipped: audioSkipped);
  }
}

/// The pieces of storage the provider touches, backed by real directories so
/// the rendered file can actually be asserted on.
class _MemoryStorage
    implements StorageService, DownloadHistoryRepository, MediaFileActions {
  _MemoryStorage(this.downloadDir);

  final Directory downloadDir;
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> receipts = [];

  @override
  Future<String?> getDownloadDirectory() async => downloadDir.path;

  @override
  Future<List<DownloadTask>> loadHistory() async =>
      history.map(DownloadTask.fromJson).toList();

  @override
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots) async {
    history = snapshots.toList();
  }

  @override
  Future<List<DownloadTask>> loadDownloadReceipts() async =>
      receipts.map(DownloadTask.fromJson).toList();

  @override
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) async {
    receipts.removeWhere((entry) => entry['id'] == snapshot['id']);
    receipts.add(snapshot);
  }

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {
    for (final snapshot in snapshots) {
      await saveDownloadReceipt(snapshot);
    }
  }

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {
    receipts.removeWhere((entry) => ids.contains(entry['id']));
  }

  @override
  bool exists(String filePath) => File(filePath).existsSync();

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _source = SlideshowSource(
  imageUrls: ['https://cdn.example.com/1.jpg', 'https://cdn.example.com/2.jpg'],
  audioUrl: 'https://cdn.example.com/song.mp3',
);

const _slideshowOption = VideoQualityOption.slideshow(
  id: 'tt_slideshow_post',
  label: SlideshowVideo(2),
  source: _source,
);

VideoMetadata _photoPostMetadata({
  List<VideoQualityOption> qualities = const [_slideshowOption],
}) => VideoMetadata(
  id: 'post',
  originalUrl: 'https://www.tiktok.com/@u/photo/1',
  title: 'Photo post',
  author: 'Author',
  coverUrl: 'https://cdn.example.com/cover.jpg',
  platform: VideoPlatform.tiktok,
  qualities: qualities,
);

Future<void> _settle() async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  late Directory root;
  late Directory downloads;
  late Directory workspace;
  late _MemoryStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('slideshow_download_test');
    downloads = Directory('${root.path}/downloads')..createSync();
    workspace = Directory('${root.path}/work')..createSync();
    storage = _MemoryStorage(downloads);
    ExtractorHttp.getOverride = (uri, _) async =>
        http.Response.bytes(const [1, 2, 3], 200);
  });

  tearDown(() {
    ExtractorHttp.resetOverrides();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  DownloadProvider provider(SlideshowRenderer renderer) => DownloadProvider(
    downloadService: InertDownloadService(),
    storageService: storage,
    historyRepository: storage,
    fileActions: storage,
    slideshowRenderer: renderer,
    slideshowWorkspace: () async =>
        Directory('${workspace.path}/${DateTime.now().microsecondsSinceEpoch}')
          ..createSync(recursive: true),
  );

  test('a slideshow option never enters the url download path', () async {
    final renderer = _FakeRenderer();
    final downloader = DownloadProvider(
      downloadService: InertDownloadService(),
      storageService: storage,
      historyRepository: storage,
      fileActions: storage,
      slideshowRenderer: renderer,
      slideshowWorkspace: () async =>
          Directory('${workspace.path}/guard')..createSync(recursive: true),
    );

    final tasks = await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );

    // Nothing to fetch means nothing queued: the URL path never sees it.
    expect(tasks, isEmpty);
    await _settle();
    // An empty download URL is the shape that would 404 if it ever reached the
    // fetcher, so no task may carry one.
    expect(downloader.allTasks.any((t) => t.downloadUrl.isEmpty), isFalse);
    expect(renderer.calls, 1);
  });

  test('an ordinary option alongside a slideshow still downloads', () async {
    final renderer = _FakeRenderer();
    const video = VideoQualityOption.video(
      id: 'v720',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn.example.com/v.mp4',
    );
    final downloader = provider(renderer);

    final tasks = await downloader.startNewDownloads(
      metadata: _photoPostMetadata(qualities: const [_slideshowOption, video]),
      qualities: const [_slideshowOption, video],
      l10n: l10n,
    );

    // The URL path keeps exactly the options it had before, and no more.
    expect(tasks, hasLength(1));
    expect(tasks.single.downloadUrl, 'https://cdn.example.com/v.mp4');
    await _settle();
    expect(renderer.calls, 1);
  });

  test('a rendered slideshow completes as a local file', () async {
    final renderer = _FakeRenderer();
    final downloader = provider(renderer);

    await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );
    await _waitUntil(
      () =>
          downloader.allTasks.any((t) => t.status == DownloadStatus.completed),
    );

    final task = downloader.allTasks.single;
    expect(task.status, DownloadStatus.completed);
    expect(task.filePath, isNotNull);
    expect(File(task.filePath!).existsSync(), isTrue);
    // Rendered into the download directory, not left in the scratch space.
    expect(task.filePath, startsWith(downloads.path));
    expect(task.format, 'mp4');
    expect(task.kind, MediaKind.video);
    // The images and the music both reached the encoder, in source order.
    expect(renderer.lastImagePaths, hasLength(2));
    expect(renderer.lastAudioPath, isNotNull);
    expect(renderer.lastPerImage, const Duration(seconds: 3));
    // History is what survives a restart; a rendered file has to be in it.
    expect(storage.receipts.single['id'], task.id);
  });

  test('the scratch directory does not outlive the render', () async {
    final downloader = provider(_FakeRenderer());

    await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );
    await _waitUntil(
      () =>
          downloader.allTasks.any((t) => t.status == DownloadStatus.completed),
    );

    // Fetched images and music are megabytes apiece; leaving one behind per
    // render fills the cache directory up silently.
    expect(workspace.listSync(), isEmpty);
  });

  test('a silent render completes, and says so', () async {
    final downloader = provider(_FakeRenderer(audioSkipped: true));

    await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );
    await _waitUntil(
      () =>
          downloader.allTasks.any((t) => t.status == DownloadStatus.completed),
    );

    final task = downloader.allTasks.single;
    // Lost music is a warning, not a failure: the video is still there.
    expect(task.status, DownloadStatus.completed);
    expect(task.errorMessage, isNotNull);
    expect(task.errorMessage, l10n.slideshowMusicUnavailable);
  });

  test('a failed render fails its task rather than the app', () async {
    final downloader = provider(
      _FakeRenderer(failWith: SlideshowFailureKind.encodeFailed),
    );

    await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );
    await _waitUntil(
      () => downloader.allTasks.any((t) => t.status == DownloadStatus.failed),
    );

    final task = downloader.allTasks.single;
    expect(task.status, DownloadStatus.failed);
    expect(task.errorMessage, isNotNull);
    // A half-written file would show up in the list as a playable download.
    expect(task.filePath, isNull);
    expect(downloads.listSync(), isEmpty);
  });

  test('a retried slideshow renders again instead of being fetched', () async {
    // retryTask re-extracts and re-queues through the URL path. A slideshow
    // option coming back out of that carries no URL, so without a branch the
    // retry queues an empty download.
    final renderer = _FakeRenderer(failWith: SlideshowFailureKind.encodeFailed);
    final downloader = provider(renderer);

    await downloader.startNewDownloads(
      metadata: _photoPostMetadata(),
      qualities: const [_slideshowOption],
      l10n: l10n,
    );
    await _waitUntil(
      () => downloader.allTasks.any((t) => t.status == DownloadStatus.failed),
    );

    final task = downloader.allTasks.single;
    await downloader.retryTask(task, l10n: l10n);
    await _settle();

    expect(renderer.calls, greaterThan(1));
    expect(downloader.allTasks.any((t) => t.downloadUrl.isEmpty), isFalse);
  });

  test(
    'a slideshow retried after a restart renders rather than fetching',
    () async {
      // A failed task is persisted like any other and comes back on the next
      // launch, but the source it was rendered from does not: that map lives in
      // memory. Re-extraction is what has to close the gap, or the retry falls
      // through to the URL path and queues an empty download.
      ExtractorHttp.postOverride = (_, _, _) async =>
          http.Response(_tiktokPhotoPost, 200);

      storage.history = [
        DownloadTask(
          id: 'restored-slideshow',
          videoId: 'tt-images-fixture',
          title: 'Photo post',
          author: 'Author',
          thumbnailUrl: '',
          downloadUrl: 'https://www.tiktok.com/@u/photo/1',
          originalUrl: 'https://www.tiktok.com/@u/photo/1',
          platform: VideoPlatform.tiktok,
          sourceOptionId: 'tt_slideshow_tt-images-fixture',
          qualityLabel: 'Slideshow video (2 images)',
          format: 'mp4',
          status: DownloadStatus.failed,
          errorMessage: 'previously failed',
        ).toJson(),
      ];

      final renderer = _FakeRenderer();
      final downloader = provider(renderer);
      await _waitUntil(() => downloader.allTasks.isNotEmpty);

      await downloader.retryTask(downloader.allTasks.single, l10n: l10n);
      await _settle();

      expect(renderer.calls, 1);
      expect(downloader.allTasks.single.status, DownloadStatus.completed);
      expect(downloader.allTasks.single.filePath, isNotNull);
    },
  );
}

final _tiktokPhotoPost = File(
  'test/fixtures/extractors/tiktok_images.json',
).readAsStringSync();
