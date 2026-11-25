import 'dart:convert';
import 'dart:io';

import 'lrclib_client.dart';

final RegExp _extension = RegExp(r'\.[^./\\]*$');

/// The lyrics file that belongs beside the audio file at [audioPath]: the
/// same name with `.lrc` in place of its extension, which is where music
/// players look for it.
String lyricsPathFor(String audioPath) {
  final separator = audioPath.lastIndexOf(RegExp(r'[/\\]'));
  final name = audioPath.substring(separator + 1);
  final base = name.contains('.') && !name.startsWith('.')
      ? name.replaceFirst(_extension, '')
      : name;
  return '${audioPath.substring(0, separator + 1)}$base.lrc';
}

/// Writes [lyrics] beside the audio file at [audioPath] and returns the
/// lyrics file's path. Throws when the file cannot be written.
Future<String> writeLyricsBeside(String audioPath, Lyrics lyrics) async {
  final path = lyricsPathFor(audioPath);
  final text = lyrics.text.endsWith('\n') ? lyrics.text : '${lyrics.text}\n';
  await File(path).writeAsString(text, encoding: utf8, flush: true);
  return path;
}
