import '../../models/download_task.dart';
import '../../models/video_platform.dart';

final RegExp _nonAlphanumeric = RegExp('[^a-zA-Z0-9]');
// Letters, their combining marks and digits of any script: a Vietnamese or
// Japanese caption names a file as well as an English one does.
final RegExp _notNameCharacter = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

const int _maximumAuthorLength = 20;
const int _maximumTitleLength = 32;

/// The name a download is saved under: the platform, who posted it, how its
/// title begins, and a slice of the task id that keeps two saves apart.
///
/// `threads_nasa_LIFTOFF_abcdef012345.mp4`. The author and the title are there
/// so a file can be found again in a Gallery; either is left out when it has
/// nothing a file name can carry.
String downloadFileName(DownloadTask task, {String? extension}) {
  final compactId = task.id.replaceAll(_nonAlphanumeric, '');
  final idPart = compactId.isEmpty
      ? 'NimbleClip'
      : compactId.substring(0, compactId.length.clamp(0, 12));
  final platformPrefix = task.platform == VideoPlatform.twitter
      ? 'x'
      : task.platform.name;
  final ext = (extension ?? task.format).replaceAll('.', '').trim();

  final author = _namePart(task.author, _maximumAuthorLength);
  final parts = [
    platformPrefix,
    // A source that names no author is credited to the platform itself, which
    // the prefix has already said.
    if (author.toLowerCase() != task.platform.name) author,
    // A caption runs on for paragraphs; its first line is its headline.
    _namePart(task.title.trim().split('\n').first, _maximumTitleLength),
    idPart,
  ].where((part) => part.isNotEmpty);
  return '${parts.join('_')}.${ext.isEmpty ? 'mp4' : ext}';
}

String _namePart(String text, int maximumLength) {
  final words = text.split(_notNameCharacter).where((word) => word.isNotEmpty);
  final buffer = StringBuffer();
  for (final word in words) {
    final separator = buffer.isEmpty ? 0 : 1;
    if (buffer.length + separator + word.length > maximumLength) {
      // A first word that is too long is cut rather than dropped; by runes,
      // so a character outside the basic plane is never split in two.
      if (buffer.isEmpty) {
        buffer.write(String.fromCharCodes(word.runes.take(maximumLength ~/ 2)));
      }
      break;
    }
    if (separator == 1) buffer.write('_');
    buffer.write(word);
  }
  return buffer.toString();
}
