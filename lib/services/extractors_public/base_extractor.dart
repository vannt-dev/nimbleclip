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

/// Why each strategy an extractor tried came back empty-handed.
///
/// Strategies recover from their own failures by returning nothing, so the
/// next one can try. The final error then names only the outcome ("no
/// video"), which reads the same whether the post is empty or the device is
/// offline. Collected here, the causes go into the diagnostics instead.
class StrategyErrors {
  final List<String> _entries = [];

  void add(String strategy, Object error) => _entries.add('$strategy: $error');

  /// Records a response that came back but was refused.
  void addStatus(String strategy, int statusCode) =>
      add(strategy, 'HTTP $statusCode');

  /// All causes in the order they happened; null when nothing failed.
  String? get summary => _entries.isEmpty ? null : _entries.join('; ');
}

abstract class BaseVideoExtractor {
  const BaseVideoExtractor();

  VideoPlatform get platform;

  /// Whether this extractor owns [url]. Defaults to matching the host against
  /// the platform table so the domain list lives in exactly one place.
  bool canHandle(String url) => UrlHelper.detectPlatform(url) == platform;

  Future<VideoMetadata> extract(String url);
}
