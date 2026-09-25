import 'dart:io';

import 'package:http/http.dart' as http;

import 'slideshow_failure.dart';

/// Fetches one media stream to [into], in byte ranges of [chunkBytes].
///
/// Ranged rather than one request: YouTube throttles a single open-ended
/// request for an adaptive stream to roughly playback speed, so a 1080p clip
/// would take as long to fetch as to watch. Each chunk is streamed straight to
/// disk, since a stream can run to hundreds of megabytes.
///
/// [onBytes] reports the running total; [isCancelled] is polled between
/// network reads and aborts with [SlideshowFailureKind.cancelled]. A server
/// that ignores the range and answers `200` is simply read to the end.
Future<void> fetchStreamToFile(
  String url,
  File into, {
  http.Client? client,
  int chunkBytes = 10 << 20,
  int attemptsPerChunk = 3,
  void Function(int receivedBytes)? onBytes,
  bool Function()? isCancelled,
}) async {
  final httpClient = client ?? http.Client();
  final sink = into.openWrite();
  var received = 0;
  int? total;
  try {
    while (total == null || received < total) {
      _throwIfCancelled(isCancelled);
      final end = received + chunkBytes - 1;
      final http.StreamedResponse response;
      try {
        response = await _sendWithRetry(
          httpClient,
          url,
          'bytes=$received-$end',
          attemptsPerChunk,
        );
      } on SlideshowException {
        rethrow;
      } catch (error) {
        throw SlideshowException(
          SlideshowFailureKind.fetchFailed,
          detail: error.toString(),
        );
      }

      final wholeBody = response.statusCode == 200;
      if (!wholeBody && response.statusCode != 206) {
        throw SlideshowException(
          SlideshowFailureKind.fetchFailed,
          detail: 'HTTP ${response.statusCode}',
        );
      }
      total = wholeBody
          ? response.contentLength
          : _totalFrom(response.headers['content-range']);

      var chunkReceived = 0;
      await for (final bytes in response.stream) {
        _throwIfCancelled(isCancelled);
        sink.add(bytes);
        received += bytes.length;
        chunkReceived += bytes.length;
        onBytes?.call(received);
      }
      if (wholeBody) break;
      // Without a total, a short range is the only sign of the end.
      if (total == null && chunkReceived < chunkBytes) break;
      if (chunkReceived == 0) {
        throw const SlideshowException(
          SlideshowFailureKind.fetchFailed,
          detail: 'the server sent an empty range',
        );
      }
    }
    await sink.flush();
  } on FileSystemException catch (error) {
    throw SlideshowException(
      _isOutOfSpace(error)
          ? SlideshowFailureKind.outOfSpace
          : SlideshowFailureKind.fetchFailed,
      detail: error.toString(),
    );
  } finally {
    await sink.close().catchError((_) {});
    if (client == null) httpClient.close();
  }
}

Future<http.StreamedResponse> _sendWithRetry(
  http.Client client,
  String url,
  String range,
  int attempts,
) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers['Range'] = range;
      final response = await client.send(request);
      // A server error is worth another try; a 4xx will not change.
      if (response.statusCode >= 500 && attempt < attempts) {
        await response.stream.drain<void>();
        continue;
      }
      return response;
    } on http.ClientException {
      if (attempt >= attempts) rethrow;
    } on SocketException {
      if (attempt >= attempts) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
  }
}

/// `bytes 0-1023/4096` → 4096. Null when the total is absent or `*`.
int? _totalFrom(String? contentRange) {
  if (contentRange == null) return null;
  final slash = contentRange.lastIndexOf('/');
  if (slash == -1) return null;
  return int.tryParse(contentRange.substring(slash + 1).trim());
}

void _throwIfCancelled(bool Function()? isCancelled) {
  if (isCancelled?.call() ?? false) {
    throw const SlideshowException(SlideshowFailureKind.cancelled);
  }
}

bool _isOutOfSpace(FileSystemException error) {
  final code = error.osError?.errorCode;
  // ENOSPC on Linux/Android, ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on Windows.
  return code == 28 || code == 112 || code == 39;
}
