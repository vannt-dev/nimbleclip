import 'dart:io';

import 'package:http/http.dart' as http;

import '../../slideshow/slideshow_failure.dart';

/// Fetches one media file to [into] in a single request.
///
/// [onBytes] reports the running total; [isCancelled] is polled between
/// network reads and aborts with [SlideshowFailureKind.cancelled].
Future<void> fetchStreamToFile(
  String url,
  File into, {
  http.Client? client,
  void Function(int receivedBytes)? onBytes,
  bool Function()? isCancelled,
}) async {
  final httpClient = client ?? http.Client();
  final sink = into.openWrite();
  var received = 0;
  try {
    final response = await httpClient.send(http.Request('GET', Uri.parse(url)));
    if (response.statusCode >= 400) {
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'HTTP ${response.statusCode}',
      );
    }
    await for (final chunk in response.stream) {
      if (isCancelled?.call() ?? false) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      sink.add(chunk);
      received += chunk.length;
      onBytes?.call(received);
    }
    await sink.flush();
  } on FileSystemException catch (error) {
    throw SlideshowException(
      isOutOfSpace(error)
          ? SlideshowFailureKind.outOfSpace
          : SlideshowFailureKind.fetchFailed,
      detail: error.toString(),
    );
  } on http.ClientException catch (error) {
    throw SlideshowException(
      SlideshowFailureKind.fetchFailed,
      detail: error.message,
    );
  } finally {
    await sink.close();
    if (client == null) httpClient.close();
  }
}

/// Asks the server for [url]'s first byte and returns the whole length it
/// reports.
Future<int> probeStreamLength(String url, {http.Client? client}) async {
  final httpClient = client ?? http.Client();
  try {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['Range'] = 'bytes=0-0';
    final response = await httpClient.send(request);
    await response.stream.drain<void>();
    final range = response.headers['content-range'];
    final total = switch (response.statusCode) {
      206 when range != null => int.tryParse(
        range.substring(range.lastIndexOf('/') + 1).trim(),
      ),
      200 => response.contentLength,
      _ => null,
    };
    if (total == null || total <= 0) {
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'no length for the stream (HTTP ${response.statusCode})',
      );
    }
    return total;
  } on http.ClientException catch (error) {
    throw SlideshowException(
      SlideshowFailureKind.fetchFailed,
      detail: error.message,
    );
  } finally {
    if (client == null) httpClient.close();
  }
}

/// True when [error] is the disk running out of room.
bool isOutOfSpace(FileSystemException error) {
  final code = error.osError?.errorCode;
  // ENOSPC on Linux/Android, ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL on Windows.
  return code == 28 || code == 112 || code == 39;
}
