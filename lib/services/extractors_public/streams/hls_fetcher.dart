import 'dart:io';

import 'package:http/http.dart' as http;

import '../../slideshow/slideshow_failure.dart';
import 'hls_decryptor.dart';

/// Fetches the segments of an HLS playlist into one file.
///
/// Not in the public core: its extractor never offers a stream, so nothing
/// reaches this. It answers as an unreadable stream if something does.
Future<void> fetchHlsToFile(
  String playlistUrl,
  File into, {
  http.Client? client,
  HlsDecryptor? decryptor,
  void Function(double fraction, int receivedBytes)? onProgress,
  bool Function()? isCancelled,
}) async {
  throw const SlideshowException(
    SlideshowFailureKind.streamUnreadable,
    detail: 'streams are not part of the public core',
  );
}
