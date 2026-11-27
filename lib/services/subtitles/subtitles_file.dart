import 'dart:convert';
import 'dart:io';

import '../../models/subtitle_file.dart';
import 'srt_converter.dart';

final RegExp _extension = RegExp(r'\.[^./\\]*$');

/// The subtitles file that belongs beside the video at [videoPath]: the same
/// name with `.srt` in place of its extension, which is where video players
/// look for it.
String subtitlesPathFor(String videoPath) {
  final separator = videoPath.lastIndexOf(RegExp(r'[/\\]'));
  final name = videoPath.substring(separator + 1);
  final base = name.contains('.') && !name.startsWith('.')
      ? name.replaceFirst(_extension, '')
      : name;
  return '${videoPath.substring(0, separator + 1)}$base.srt';
}

/// Writes [subtitles] as an `.srt` beside the video at [videoPath] and
/// returns its path, or null when they hold no line to show. Throws when the
/// file cannot be written.
Future<String?> writeSubtitlesBeside(
  String videoPath,
  SubtitleFile subtitles,
) async {
  final srt = webVttToSrt(subtitles.webVtt);
  if (srt.trim().isEmpty) return null;
  final path = subtitlesPathFor(videoPath);
  await File(path).writeAsString(srt, encoding: utf8, flush: true);
  return path;
}
