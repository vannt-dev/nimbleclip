import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/download_service.dart';

DownloadTask task({
  String id = 'abcdef01-2345-6789-abcd-ef0123456789',
  String title = 'A video',
  String format = 'mp4',
  bool isImage = false,
}) {
  return DownloadTask(
    id: id,
    videoId: 'v1',
    title: title,
    author: 'Someone',
    thumbnailUrl: '',
    downloadUrl: 'https://cdn.example.com/v.mp4',
    originalUrl: 'https://example.com/watch?v=1',
    platform: VideoPlatform.generic,
    qualityLabel: '720p',
    format: format,
    isImage: isImage,
  );
}

void main() {
  group('DownloadTask JSON round trip', () {
    test('preserves a completed task', () {
      final original = task()
        ..status = DownloadStatus.completed
        ..progress = 1.0
        ..totalBytes = 2048
        ..receivedBytes = 2048
        ..filePath = '/tmp/v.mp4'
        ..isSavedToGallery = true;

      final restored = DownloadTask.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.status, DownloadStatus.completed);
      expect(restored.totalBytes, 2048);
      expect(restored.filePath, '/tmp/v.mp4');
      expect(restored.isSavedToGallery, isTrue);
    });

    test('demotes an interrupted download to failed', () {
      // Regression: a task persisted mid-download came back as still active and
      // stayed pinned to the "downloading" list forever, with nothing running.
      for (final status in DownloadTask.transientStatuses) {
        final interrupted = task()..status = status;
        final restored = DownloadTask.fromJson(interrupted.toJson());

        expect(restored.status, DownloadStatus.failed, reason: status.name);
        expect(restored.isActive, isFalse, reason: status.name);
        expect(restored.isDone, isTrue, reason: status.name);
      }
    });

    test('keeps terminal statuses as they were', () {
      for (final status in const [
        DownloadStatus.completed,
        DownloadStatus.handedOff,
        DownloadStatus.failed,
        DownloadStatus.cancelled,
      ]) {
        final restored = DownloadTask.fromJson(
          (task()..status = status).toJson(),
        );
        expect(restored.status, status);
      }
    });

    test('survives a malformed payload', () {
      final restored = DownloadTask.fromJson(const {});
      expect(restored.title, 'Untitled Video');
      expect(restored.platform, VideoPlatform.generic);
      expect(restored.status, DownloadStatus.completed);
    });

    test('preserves the image media type', () {
      final restored = DownloadTask.fromJson(
        task(format: 'jpg', isImage: true).toJson(),
      );
      expect(restored.format, 'jpg');
      expect(restored.isImage, isTrue);
    });
  });

  group('DownloadTask.withRefreshedSource', () {
    test('swaps the URL and re-queues without losing identity', () {
      final original = task()
        ..status = DownloadStatus.failed
        ..errorMessage = 'expired';

      final refreshed = original.withRefreshedSource(
        downloadUrl: 'https://cdn.example.com/fresh.mp4',
        headers: {'Referer': 'https://example.com'},
      );

      expect(refreshed.id, original.id);
      expect(refreshed.createdAt, original.createdAt);
      expect(refreshed.downloadUrl, 'https://cdn.example.com/fresh.mp4');
      expect(refreshed.headers, {'Referer': 'https://example.com'});
      expect(refreshed.status, DownloadStatus.queued);
      expect(refreshed.errorMessage, isNull);
    });
  });

  group('DownloadService.buildFileName', () {
    final service = DownloadService();

    test('replaces characters the filesystem rejects', () {
      final name = service.buildFileName(task(title: r'a/b\c:d*e?f"g<h>i|j'));
      expect(name, isNot(contains(RegExp(r'[\\/:*?"<>|]'))));
      expect(name, endsWith('.mp4'));
    });

    test('keeps a readable base and appends a short id', () {
      expect(
        service.buildFileName(task(title: 'My Clip')),
        'My Clip_abcdef.mp4',
      );
    });

    test('falls back when the title sanitises to nothing', () {
      expect(
        service.buildFileName(task(title: '///')),
        'NimbleClip_abcdef.mp4',
      );
      expect(
        service.buildFileName(task(title: '   ')),
        'NimbleClip_abcdef.mp4',
      );
    });

    test('truncates very long titles', () {
      final name = service.buildFileName(task(title: 'x' * 500));
      expect(name.length, lessThan(140));
      expect(name, endsWith('.mp4'));
    });

    test('does not crash on a short or empty id', () {
      // Regression: substring(0, 6) threw RangeError for a task restored from a
      // history entry with a missing id.
      expect(service.buildFileName(task(id: '')), 'A video.mp4');
      expect(service.buildFileName(task(id: 'ab')), 'A video_ab.mp4');
    });

    test('normalises the extension', () {
      expect(service.buildFileName(task(format: '.mp3')), endsWith('.mp3'));
      expect(service.buildFileName(task(format: '')), endsWith('.mp4'));
    });
  });
}
