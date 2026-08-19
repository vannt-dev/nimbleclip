import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nimble_clip/core/utils/platform_file.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/download_service.dart';

/// On-device checks for the Android storage and download paths.
///
/// These exist because `android:requestLegacyExternalStorage` was removed from
/// the manifest: everything here has to work under scoped storage, using only
/// the app's own external files directory and MediaStore. They also cover the
/// resume-by-byte-range path and confirm that cleartext to the dev host still
/// passes the network security config.
///
/// Run the fixture server on the host first — the emulator reaches it at
/// 10.0.2.2:
///
///   node tool/fixture_server.js
///   flutter test integration_test/android_storage_test.dart -d emulator-5554
const String fixtureHost = 'http://10.0.2.2:8097';

DownloadTask fixtureTask({
  required String id,
  required String title,
  String query = '',
}) {
  return DownloadTask(
    id: id,
    videoId: 'fixture',
    title: title,
    author: 'Fixture',
    thumbnailUrl: '',
    downloadUrl: '$fixtureHost/sample.mp4$query',
    originalUrl: '$fixtureHost/sample.mp4',
    platform: VideoPlatform.generic,
    qualityLabel: 'Original',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));

  final service = DownloadService();
  late String downloadDir;
  late int fixtureSize;
  late List<int> fixtureBytes;

  setUpAll(() async {
    final dir = await PlatformFileHelper.getDownloadDirectoryPath();
    expect(dir, isNotNull, reason: 'no download directory was resolved');
    downloadDir = dir!;

    // Taken from the fixture rather than hard-coded, so swapping the sample
    // video does not silently invalidate the byte-count assertions.
    fixtureBytes = await _fetchFixture();
    fixtureSize = fixtureBytes.length;
    expect(fixtureSize, greaterThan(100000),
        reason: 'fixture server not reachable at $fixtureHost — '
            'start it with `node tool/fixture_server.js`');
  });

  group('scoped storage', () {
    test('download directory is the app-owned external files dir', () async {
      // Under scoped storage this is the only external location the app may
      // write to without holding any permission at all.
      expect(downloadDir, contains('/Android/data/'));
      expect(downloadDir, endsWith('/NimbleClip'));
      expect(Directory(downloadDir).existsSync(), isTrue);
    });

    test('the directory is readable and writable without permissions', () async {
      final probe = File('$downloadDir/.probe');
      await probe.writeAsString('scoped-storage-ok');
      expect(await probe.readAsString(), 'scoped-storage-ok');
      await probe.delete();
      expect(probe.existsSync(), isFalse);
    });
  });

  group('download over cleartext to the dev host', () {
    test('completes and writes the whole file', () async {
      // Also proves network_security_config still allows 10.0.2.2 now that the
      // blanket usesCleartextTraffic flag is gone.
      final task = fixtureTask(id: 'aaaaaa01-full', title: 'Full download');
      String? failure;

      await service.startDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: false,
        onProgress: (_, _, _, _, _) {},
        onComplete: (_, _) {},
        onError: (_, error) => failure = error,
      );

      expect(failure, isNull, reason: 'download reported: $failure');
      expect(task.status, DownloadStatus.completed);

      final file = File(task.filePath!);
      expect(file.existsSync(), isTrue);
      expect(await file.length(), fixtureSize);
      expect(task.receivedBytes, fixtureSize);

      // A real MP4 must arrive, not an error page renamed to .mp4.
      final header = await file.openRead(4, 8).first;
      expect(String.fromCharCodes(header), 'ftyp');

      await file.delete();
    });

    test('resumes from a partial file using a byte range', () async {
      final task = fixtureTask(id: 'aaaaaa02-resu', title: 'Resumable');
      final savePath = '$downloadDir/${service.buildFileName(task)}';

      // Seed a partial file, as a pause would have left behind.
      final partialBytes = fixtureSize ~/ 3;
      await File(savePath).writeAsBytes(fixtureBytes.sublist(0, partialBytes));
      task.filePath = savePath;

      var sawResumeOffset = false;
      await service.startDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: false,
        onProgress: (_, _, received, _, _) {
          // Progress is reported on the whole-file scale, so the first callback
          // must already be past the bytes that were on disk.
          if (received > partialBytes) sawResumeOffset = true;
        },
        onComplete: (_, _) {},
        onError: (_, _) {},
      );

      expect(task.status, DownloadStatus.completed);
      expect(sawResumeOffset, isTrue);

      final file = File(savePath);
      expect(await file.length(), fixtureSize,
          reason: 'resume appended the wrong number of bytes');
      expect(await file.readAsBytes(), equals(fixtureBytes),
          reason: 'resumed file does not match the original byte-for-byte');

      await file.delete();
    });

    test('restarts cleanly when the server ignores Range', () async {
      // Appending onto a partial file when the server replies 200 would splice
      // two copies together; the service must discard and restart instead.
      final task = fixtureTask(
        id: 'aaaaaa03-nora',
        title: 'No range',
        query: '?norange',
      );
      final savePath = '$downloadDir/${service.buildFileName(task)}';
      await File(savePath).writeAsBytes(List.filled(fixtureSize ~/ 5, 0x41));
      task.filePath = savePath;

      await service.startDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: false,
        onProgress: (_, _, _, _, _) {},
        onComplete: (_, _) {},
        onError: (_, _) {},
      );

      expect(task.status, DownloadStatus.completed);
      final file = File(savePath);
      expect(await file.length(), fixtureSize,
          reason: 'partial bytes were spliced onto a fresh response');
      expect(await file.readAsBytes(), equals(fixtureBytes));

      await file.delete();
    });

    test('restarts if the real transfer returns 200 after a valid probe',
        () async {
      final task = fixtureTask(
        id: 'aaaaaa05-flak',
        title: 'Flaky range',
        query: '?flakyrange=aaaaaa05',
      );
      final savePath = '$downloadDir/${service.buildFileName(task)}';
      await File(savePath).writeAsBytes(List.filled(fixtureSize ~/ 4, 0x42));
      task.filePath = savePath;

      await service.startDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: false,
        onProgress: (_, _, _, _, _) {},
        onComplete: (_, _) {},
        onError: (_, _) {},
      );

      expect(task.status, DownloadStatus.completed);
      expect(await File(savePath).readAsBytes(), equals(fixtureBytes),
          reason: 'a full 200 response was appended after a successful probe');

      await File(savePath).delete();
    });
  });

  group('gallery publishing via MediaStore', () {
    test('saveToGallery succeeds without legacy external storage', () async {
      final task = fixtureTask(id: 'aaaaaa04-gall', title: 'Gallery save');
      String? failure;

      await service.startDownload(
        task: task,
        l10n: l10n,
        autoSaveToGallery: true,
        onProgress: (_, _, _, _, _) {},
        onComplete: (_, _) {},
        onError: (_, error) => failure = error,
      );

      expect(failure, isNull, reason: 'download reported: $failure');
      expect(task.status, DownloadStatus.completed);
      expect(task.isSavedToGallery, isTrue,
          reason: 'MediaStore insert failed under scoped storage');

      await File(task.filePath!).delete();
    });
  });

  group('cache accounting', () {
    test('reports and clears the download directory', () async {
      final file = File('$downloadDir/cache_probe.bin');
      await file.writeAsBytes(List.filled(4096, 0));

      // Directory listings on the emulator's FUSE-backed external storage have
      // been seen to lag a moment behind a just-created file, so poll briefly
      // rather than reading once. Still fails if the size never becomes right.
      var reported = 0;
      for (var attempt = 0; attempt < 20; attempt++) {
        reported = await PlatformFileHelper.calculateCacheSize(downloadDir);
        if (reported >= 4096) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(reported, greaterThanOrEqualTo(4096));

      await PlatformFileHelper.clearDownloads(downloadDir);
      expect(file.existsSync(), isFalse);
      expect(await PlatformFileHelper.calculateCacheSize(downloadDir), 0);
    });
  });
}

Future<List<int>> _fetchFixture() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse('$fixtureHost/sample.mp4'));
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  } catch (_) {
    return const [];
  } finally {
    client.close();
  }
}
