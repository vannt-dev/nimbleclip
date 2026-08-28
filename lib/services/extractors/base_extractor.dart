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

  const ExtractionException(
    this.failure, {
    this.diagnosticCode,
    this.attemptedStrategies = const [],
  });

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
