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
/// A request that goes quiet for [segmentTimeout] is given up and tried again:
/// a stream is hundreds of requests, and one that hangs would otherwise hold
/// the whole download at whatever it had reached. The limit is on silence, not
/// on the whole request, so a large segment on a slow line is not cut short.
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
  final parts = <File>[];
  try {
    final base = Uri.parse(playlistUrl);
    final playlist = File('${into.path}.playlist');
    parts.add(playlist);
    await _fetch(
      httpClient,
      HlsSegment(playlistUrl),
      playlist,
      attemptsPerSegment,
      segmentTimeout,
    );
    final media = parseHlsMedia(
      utf8.decode(await playlist.readAsBytes(), allowMalformed: true),
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

    final out = sink = into.openWrite();
    var received = 0;

    // Each segment goes to a file of its own and is then copied on in order.
    // Never through memory: a stream cut into a few segments, or served as
    // one, has segments of hundreds of megabytes, and a phone that holds four
    // of those at once is a phone whose app has just been killed.
    Future<void> append(List<HlsSegment> batch, int firstIndex) async {
      final files = [
        for (var offset = 0; offset < batch.length; offset++)
          File('${into.path}.part${firstIndex + offset}'),
      ];
      parts.addAll(files);
      await Future.wait([
        for (var offset = 0; offset < batch.length; offset++)
          _fetch(
            httpClient,
            batch[offset],
            files[offset],
            attemptsPerSegment,
            segmentTimeout,
          ),
      ]);
      for (final file in files) {
        received += await file.length();
        await out.addStream(file.openRead());
        await file.delete();
        parts.remove(file);
      }
      await out.flush();
    }

    final initialization = media.initialization;
    if (initialization != null) await append([initialization], -1);

    // A few at a time: one connection per segment in turn would fetch a long
    // video at a fraction of the line's speed.
    final segments = media.segments;
    for (var start = 0; start < segments.length; start += concurrency) {
      if (isCancelled?.call() ?? false) {
        throw const SlideshowException(SlideshowFailureKind.cancelled);
      }
      final batch = segments.skip(start).take(concurrency).toList();
      await append(batch, start);
      onProgress?.call((start + batch.length) / segments.length, received);
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
    for (final part in parts) {
      try {
        if (part.existsSync()) part.deleteSync();
      } catch (_) {
        // The workspace is deleted whole by the caller; this is only tidiness.
      }
    }
    if (client == null) httpClient.close();
  }
}

/// Writes what [segment] addresses to [into], replacing whatever an earlier
/// attempt left there.
Future<void> _fetch(
  http.Client client,
  HlsSegment segment,
  File into,
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
        final sink = into.openWrite();
        try {
          await sink.addStream(response.stream.timeout(timeout));
        } finally {
          await sink.close();
        }
        return;
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
