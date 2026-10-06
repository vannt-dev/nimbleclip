import 'dart:io';

import 'package:http/http.dart' as http;

import '../hls/hls_fetcher.dart';
import '../slideshow/slideshow_failure.dart';
import 'dash_manifest.dart';

/// Fetches every segment of the representation [representationId] of the
/// manifest at [manifestUrl] into the one file [into], in playing order.
///
/// The manifest is read again here rather than carried from the extraction:
/// the addresses in it are often signed and short-lived. Its segments are
/// fragments of one MP4 behind an initialization header, or one MP4 whole, so
/// the joined file is one the platform's demuxer reads as it stands.
///
/// A broadcast still going on is refused with
/// [SlideshowFailureKind.streamLive], content under a key system with
/// [SlideshowFailureKind.streamProtected]. The remaining arguments are those
/// of [fetchSegmentsToFile].
Future<void> fetchDashToFile(
  String manifestUrl,
  String representationId,
  File into, {
  http.Client? client,
  int concurrency = 4,
  int attemptsPerSegment = 3,
  Duration segmentTimeout = const Duration(seconds: 30),
  void Function(double fraction, int receivedBytes)? onProgress,
  bool Function()? isCancelled,
}) => fetchSegmentsToFile(
  (httpClient) async {
    final DashManifest manifest;
    try {
      manifest = parseDashManifest(
        await fetchStreamIndex(
          httpClient,
          manifestUrl,
          File('${into.path}.manifest'),
          attempts: attemptsPerSegment,
          timeout: segmentTimeout,
        ),
        Uri.parse(manifestUrl),
      );
    } on FormatException catch (error) {
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: error.message,
      );
    }
    if (manifest.isProtected) {
      throw const SlideshowException(SlideshowFailureKind.streamProtected);
    }
    if (manifest.isLive) {
      throw const SlideshowException(SlideshowFailureKind.streamLive);
    }
    final representation = manifest.byId(representationId);
    if (representation == null) {
      // The manifest changed between the analysis and the download.
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'the manifest no longer lists $representationId',
      );
    }
    return representation.media;
  },
  into,
  client: client,
  concurrency: concurrency,
  attemptsPerSegment: attemptsPerSegment,
  segmentTimeout: segmentTimeout,
  onProgress: onProgress,
  isCancelled: isCancelled,
);
