import '../../core/utils/url_helper.dart';
import 'extraction_failure.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';

/// Thrown when a link is recognised but no downloadable stream could be found.
///
/// Carries the failure's identity rather than a sentence, so the layer stays
/// free of presentation text. Callers render it with
/// `describeExtractionFailure`.
class ExtractionException implements Exception {
  final ExtractionFailure failure;
  final String? diagnosticCode;
  final List<String> attemptedStrategies;

  /// The error an earlier strategy hit before the extractor fell back.
  ///
  /// [failure] belongs to the last strategy tried, which can hide the real
  /// cause: a YouTube Shorts share link once failed in the native client as
  /// an invalid URL, yet reached the user as "no streams" from the fallback.
  /// Diagnostics only; it is never shown as the error message.
  final String? suppressedError;

  const ExtractionException(
    this.failure, {
    this.diagnosticCode,
    this.attemptedStrategies = const [],
    this.suppressedError,
  });

  ExtractionException withSuppressedError(String error) => ExtractionException(
    failure,
    diagnosticCode: diagnosticCode,
    attemptedStrategies: attemptedStrategies,
    suppressedError: error,
  );

  @override
  String toString() => 'ExtractionException(${failure.kind.name})';
}

abstract class BaseVideoExtractor {
  const BaseVideoExtractor();

  VideoPlatform get platform;

  /// Whether this extractor owns [url]. Defaults to matching the host against
  /// the platform table so the domain list lives in exactly one place.
  bool canHandle(String url) => UrlHelper.detectPlatform(url) == platform;

  Future<VideoMetadata> extract(String url);
}
