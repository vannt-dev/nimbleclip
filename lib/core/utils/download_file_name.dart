import '../../models/download_task.dart';
import '../../models/video_platform.dart';

final RegExp _nonAlphanumeric = RegExp('[^a-zA-Z0-9]');

/// The name a download is saved under: the platform and a slice of the task
/// id that keeps two saves apart.
///
/// `tiktok_a474a6364e1b.mp4`. Nothing of the author or the caption goes in:
/// a caption in decorated letters or several lines long made names that were
/// hard to read and to type, and the app's own list already shows the title.
String downloadFileName(DownloadTask task, {String? extension}) {
  final compactId = task.id.replaceAll(_nonAlphanumeric, '');
  final idPart = compactId.isEmpty
      ? 'NimbleClip'
      : compactId.substring(0, compactId.length.clamp(0, 12));
  final platformPrefix = task.platform == VideoPlatform.twitter
      ? 'x'
      : task.platform.name;
  final ext = (extension ?? task.format).replaceAll('.', '').trim();
  return '${platformPrefix}_$idPart.${ext.isEmpty ? 'mp4' : ext}';
}
