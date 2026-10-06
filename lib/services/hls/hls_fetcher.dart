import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../slideshow/slideshow_failure.dart';
import 'hls_playlist.dart';

/// Fetches every segment of the media playlist at [playlistUrl] into the one
/// file [into], in playing order.
///
/// MPEG-TS segments are made to be played end to end, and fragmented-MP4
/// segments behind their initialization header are one fragmented MP4, so the
/// joined file is a stream the platform's demuxer reads as it stands.
///
/// A request that stalls for [segmentTimeout] is given up and tried again: a
/// stream is hundreds of requests, and one that hangs would otherwise hold the
/// whole download at whatever it had reached.
///
/// [onProgress] reports the share of segments written and the bytes so far;
/// [isCancelled] is polled between segments and aborts with
/// [SlideshowFailureKind.cancelled]. A live or encrypted stream is refused
/// with [SlideshowFailureKind.streamLive] or
/// [SlideshowFailureKind.streamProtected].
Future<void> fetchHlsToFile(
  String playlistUrl,
  File into, {
  http.Client? client,
  int concurrency = 4,
  int attemptsPerSegment = 3,
  Duration segmentTimeout = const Duration(seconds: 30),
  void Function(double fraction, int receivedBytes)? onProgress,
  bool Function()? isCancelled,
}) async {
  final httpClient = client ?? http.Client();
  IOSink? sink;
  try {
    final base = Uri.parse(playlistUrl);
    Future<List<int>> get(HlsSegment segment) =>
        _get(httpClient, segment, attemptsPerSegment, segmentTimeout);

    final media = parseHlsMedia(
      utf8.decode(await get(HlsSegment(playlistUrl)), allowMalformed: true),
      base,
    );
    if (media.isEncrypted) {
      throw const SlideshowException(SlideshowFailureKind.streamProtected);
    }
    if (!media.isComplete) {
      throw const SlideshowException(SlideshowFailureKind.streamLive);
    }
    if (media.segments.isEmpty) {
      throw const SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'the playlist lists no segments',
      );
    }

    sink = into.openWrite();
    var received = 0;
    final initialization = media.initialization;
    if (initialization != null) {
      final bytes = await get(initialization);
      sink.add(bytes);
      received += bytes.length;
    }

    // A few at a time, written in order: segments are a few megabytes each,
    // so a batch fits in memory, and one connection per segment in turn would
    // fetch a long video at a fraction of the line's speed.
    final segments = media.segments;
    for (var start = 0; start < segments.length; start += concurrency) {
      if (isCancelled?.call() ?? false) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      final batch = segments.skip(start).take(concurrency);
      final bodies = await Future.wait(batch.map(get));
      for (final bytes in bodies) {
        sink.add(bytes);
        received += bytes.length;
      }
      // Not once per batch for nothing: an unflushed sink keeps every segment
      // of a long video in memory until the end.
      await sink.flush();
      final done = start + bodies.length;
      onProgress?.call(done / segments.length, received);
    }
  } on SlideshowException {
    rethrow;
  } catch (error) {
    throw SlideshowException(
      SlideshowFailureKind.fetchFailed,
      detail: error.toString(),
    );
  } finally {
    try {
      await sink?.close();
    } catch (_) {
      // The failure that got us here is the one worth reporting.
    }
    if (client == null) httpClient.close();
  }
}

Future<List<int>> _get(
  http.Client client,
  HlsSegment segment,
  int attempts,
  Duration timeout,
) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final request = http.Request('GET', Uri.parse(segment.url));
      final range = segment.range;
      if (range != null) {
        request.headers['Range'] =
            'bytes=${range.start}-${range.start + range.length - 1}';
      }
      final response = await client.send(request).timeout(timeout);
      // A server error is worth another try; a 4xx will not change.
      if (response.statusCode >= 500 && attempt < attempts) {
        await response.stream.drain<void>();
      } else if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw SlideshowException(
          SlideshowFailureKind.fetchFailed,
          detail: 'HTTP ${response.statusCode}',
        );
      } else {
        return await response.stream.toBytes().timeout(timeout);
      }
    } on TimeoutException {
      if (attempt >= attempts) rethrow;
    } on http.ClientException {
      if (attempt >= attempts) rethrow;
    } on SocketException {
      if (attempt >= attempts) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
  }
}
