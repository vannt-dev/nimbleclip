import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/models/video_metadata.dart';
import 'package:nimble_clip/models/video_platform.dart';
import 'package:nimble_clip/services/download_service.dart';

DownloadTask task({
  String id = 'abcdef01-2345-6789-abcd-ef0123456789',
  String title = 'A video',
  String format = 'mp4',
  bool isImage = false,
  VideoPlatform platform = VideoPlatform.generic,
  String author = '',
}) {
  return DownloadTask(
    id: id,
    videoId: 'v1',
    title: title,
    author: author,
    thumbnailUrl: '',
    downloadUrl: 'https://cdn.example.com/v.mp4',
    originalUrl: 'https://example.com/watch?v=1',
    platform: platform,
    qualityLabel: '720p',
    format: format,
    kind: isImage ? MediaKind.image : MediaKind.video,
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
        ..galleryUri = 'content://media/external/video/42'
        ..isSavedToGallery = true;

      final restored = DownloadTask.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.status, DownloadStatus.completed);
      expect(restored.totalBytes, 2048);
      expect(restored.filePath, '/tmp/v.mp4');
      expect(restored.galleryUri, 'content://media/external/video/42');
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

    test('preserves the stable source option id', () {
      final original = DownloadTask(
        id: 'task',
        videoId: 'post',
        title: 'Image',
        author: 'Author',
        thumbnailUrl: '',
        downloadUrl: 'https://cdn.example/image.jpg',
        originalUrl: 'https://example/post',
        platform: VideoPlatform.instagram,
        sourceOptionId: 'image-3',
        qualityLabel: 'Image 3',
        format: 'jpg',
        kind: MediaKind.image,
      );

      expect(
        DownloadTask.fromJson(original.toJson()).sourceOptionId,
        'image-3',
      );
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

  test('progress notifications are coalesced per task', () async {
    final download = task();
    var notifications = 0;
    download.addListener(() => notifications++);

    download.notifyProgressChanged();
    download.notifyProgressChanged();
    download.notifyProgressChanged();
    expect(notifications, 1);

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(notifications, 2);
    download.dispose();
  });

  group('DownloadService.buildFileName', () {
    final service = DownloadService();

    test('names the platform and the task, nothing else', () {
      expect(
        service.buildFileName(task(title: 'My Clip', author: 'nasa')),
        'generic_abcdef012345.mp4',
      );
    });

    test('keeps the author and the caption out, whatever they hold', () {
      // A TikTok caption in decorated letters once produced
      // tiktok_ℂ𝕙𝕚𝕝𝕖_𝕚𝕦_𝕠𝕚_Xộn_lào_quâ_à_rhycap_hungan_<id>.
      expect(
        service.buildFileName(
          task(
            title: 'ℂ𝕙𝕚𝕝𝕖 𝕚𝕦 𝕠𝕚\nXộn lào quâ à #rhycap',
            author: 'hungan',
          ),
        ),
        'generic_abcdef012345.mp4',
      );
      expect(
        service.buildFileName(task(title: r'a/b\c:d*e?"f<g>h|i')),
        'generic_abcdef012345.mp4',
      );
      expect(
        service.buildFileName(task(title: 'x' * 500, author: 'y' * 500)),
        'generic_abcdef012345.mp4',
      );
    });

    test('does not crash on a short or empty id', () {
      // Regression: substring(0, 6) threw RangeError for a task restored from a
      // history entry with a missing id.
      expect(
        service.buildFileName(task(id: '', title: '')),
        'generic_NimbleClip.mp4',
      );
      expect(
        service.buildFileName(task(id: 'ab', title: '')),
        'generic_ab.mp4',
      );
    });

    test('normalises the extension', () {
      expect(service.buildFileName(task(format: '.mp3')), endsWith('.mp3'));
      expect(service.buildFileName(task(format: '')), endsWith('.mp4'));
      expect(
        service.buildFileName(task(title: ''), extension: 'webm'),
        'generic_abcdef012345.webm',
      );
    });

    test('prefixes every file with its source platform', () {
      for (final platform in VideoPlatform.values) {
        final expectedPrefix = platform == VideoPlatform.twitter
            ? 'x'
            : platform.name;
        expect(
          service.buildFileName(task(platform: platform, title: '')),
          '${expectedPrefix}_abcdef012345.mp4',
        );
      }
    });
  });

  group('a title written by an older build', () {
    test('has its descriptor replaced by the stored label', () {
      final json = task(title: "Post - Instance of 'ImageIndex'").toJson()
        ..['qualityLabel'] = 'Image 7';
      expect(DownloadTask.fromJson(json).title, 'Post - Image 7');
    });

    test('is left alone when it is already text', () {
      final json = task(title: 'Post - Image 7').toJson();
      expect(DownloadTask.fromJson(json).title, 'Post - Image 7');
    });
  });
}
