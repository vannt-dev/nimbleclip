import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_options.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/providers/download_provider.dart';
import 'package:nimble_clip/services/download_service.dart';
import 'package:nimble_clip/services/extractors/registry.dart';

import 'support/memory_storage.dart';

/// Hands back the same result for any link.
class _FixedRegistry extends ExtractorRegistry {
  _FixedRegistry(this.metadata);

  VideoMetadata metadata;

  @override
  Future<VideoMetadata> extract(String rawUrl) async => metadata;
}

/// Fails the first start of each download and records what it was given.
class _FailingOnceGateway implements DownloadGateway {
  final List<DownloadTask> started = [];

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {
    started.add(task);
    if (started.length > 1) return;
    task
      ..status = DownloadStatus.failed
      ..errorMessage = 'cut off';
    onError(task, 'cut off');
  }

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() {}
}

VideoMetadata _song({int? partBytes, String address = 'first'}) =>
    VideoMetadata(
      id: 'song',
      originalUrl: 'https://example.com/song',
      title: 'A song',
      author: 'Author',
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption.audio(
          id: 'audio',
          label: const AudioM4a(128),
          quality: 'Audio (128 kbps)',
          format: 'm4a',
          downloadUrl: 'https://cdn.example.com/$address.m4a',
          partBytes: partBytes,
        ),
      ],
    );

Future<void> _until(bool Function() done) async {
  for (var attempt = 0; attempt < 400 && !done(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'the wait ran out');
}

/// An extractor may ask for a file to be fetched a range at a time by naming
/// the size of the ranges on its option. The app carries that number with the
/// download and decides nothing about it.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  DownloadTask task({int? partBytes}) => DownloadTask(
    id: 'task',
    videoId: 'song',
    title: 'A song',
    author: 'Author',
    thumbnailUrl: '',
    downloadUrl: 'https://cdn.example.com/first.m4a',
    originalUrl: 'https://example.com/song',
    platform: VideoPlatform.generic,
    qualityLabel: 'M4A audio (128 kbps)',
    format: 'm4a',
    kind: MediaKind.audio,
    partBytes: partBytes,
  );

  test('a task keeps its part size when it is stored and read back', () {
    final stored = task(partBytes: 4096).toJson();
    expect(stored['partBytes'], 4096);
    expect(DownloadTask.fromJson(stored).partBytes, 4096);

    // One fetched whole says nothing, as every task did before part sizes.
    final whole = task().toJson();
    expect(whole.containsKey('partBytes'), isFalse);
    expect(DownloadTask.fromJson(whole).partBytes, isNull);
  });

  test('a refreshed address is fetched the way its own option says', () {
    final refreshed = task(partBytes: 4096).withRefreshedSource(
      downloadUrl: 'https://cdn.example.com/second.m4a',
      partBytes: 8192,
    );
    expect(refreshed.partBytes, 8192);

    // The new address may be one that is fetched whole.
    final whole = task(
      partBytes: 4096,
    ).withRefreshedSource(downloadUrl: 'https://cdn.example.com/second.m4a');
    expect(whole.partBytes, isNull);
  });

  group('through the provider', () {
    late Directory downloads;
    late MemoryStorage storage;

    setUp(() {
      downloads = Directory.systemTemp.createTempSync('part_size_test');
      storage = MemoryStorage(downloads);
    });

    tearDown(() {
      if (downloads.existsSync()) downloads.deleteSync(recursive: true);
    });

    test('a download carries the size its option names, and a retry the size '
        'the option names then', () async {
      final gateway = _FailingOnceGateway();
      final registry = _FixedRegistry(_song(partBytes: 4096));
      final provider = DownloadProvider(
        downloadService: gateway,
        storageService: storage,
        historyRepository: storage,
        fileActions: storage,
        extractorRegistry: registry,
      );
      addTearDown(provider.dispose);

      await provider.startNewDownloads(
        metadata: registry.metadata,
        qualities: registry.metadata.qualities,
        l10n: l10n,
        options: const DownloadOptions(autoSaveToGallery: false),
      );
      await _until(() => gateway.started.length == 1);
      expect(gateway.started.single.partBytes, 4096);
      await _until(
        () => provider.allTasks.single.status == DownloadStatus.failed,
      );

      // The link is read again for a retry, and what comes back decides.
      registry.metadata = _song(partBytes: 8192, address: 'second');
      await provider.retryTask(provider.allTasks.single, l10n: l10n);
      await _until(() => gateway.started.length == 2);
      expect(
        gateway.started.last.downloadUrl,
        'https://cdn.example.com/second.m4a',
      );
      expect(gateway.started.last.partBytes, 8192);
    });

    test('an option that names no size is fetched whole', () async {
      final gateway = _FailingOnceGateway();
      final registry = _FixedRegistry(_song());
      final provider = DownloadProvider(
        downloadService: gateway,
        storageService: storage,
        historyRepository: storage,
        fileActions: storage,
        extractorRegistry: registry,
      );
      addTearDown(provider.dispose);

      await provider.startNewDownloads(
        metadata: registry.metadata,
        qualities: registry.metadata.qualities,
        l10n: l10n,
        options: const DownloadOptions(autoSaveToGallery: false),
      );
      await _until(() => gateway.started.length == 1);
      expect(gateway.started.single.partBytes, isNull);
    });
  });
}
