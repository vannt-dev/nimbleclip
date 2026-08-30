import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/services/download_service.dart';

/// Keeps the real native gateway — and its process-wide update stream — out of
/// widget tests.
///
/// That stream can only be listened to once per process, so a second test
/// building a real [DownloadProvider] fails with "Stream has already been
/// listened to" and takes every provider below it down with it. Any widget
/// test that builds a screen holding a download provider needs this.
class InertDownloadService implements DownloadGateway {
  bool disposed = false;

  @override
  Future<void> startDownload({
    required DownloadTask task,
    required DownloadProgressCallback onProgress,
    required void Function(DownloadTask task, String filePath) onComplete,
    required void Function(DownloadTask task, String error) onError,
    required AppLocalizations l10n,
    bool autoSaveToGallery = true,
  }) async {}

  @override
  void cancelDownload(String taskId) {}

  @override
  bool pauseDownload(String taskId) => false;

  @override
  bool isRunning(String taskId) => false;

  @override
  void dispose() => disposed = true;
}
