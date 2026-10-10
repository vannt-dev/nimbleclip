import 'dart:io';

import 'package:http/http.dart' as http;

import '../../slideshow/slideshow_failure.dart';

/// Fetches the segments of one representation of a DASH manifest into one
/// file.
///
/// Not in the public core, as for HLS: it answers as an unreadable stream.
Future<void> fetchDashToFile(
  String manifestUrl,
  String representationId,
  File into, {
  http.Client? client,
  void Function(double fraction, int receivedBytes)? onProgress,
  bool Function()? isCancelled,
}) async {
  throw const SlideshowException(
    SlideshowFailureKind.streamUnreadable,
    detail: 'streams are not part of the public core',
  );
}
