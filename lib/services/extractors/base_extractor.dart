import '../../core/utils/url_helper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';

/// Thrown when a link is recognised but no downloadable stream could be found.
///
/// Carries a message already phrased for the user, so the UI can surface it
/// without unwrapping nested `Exception: Exception: ...` prefixes.
class ExtractionException implements Exception {
  final String message;
  const ExtractionException(this.message);

  @override
  String toString() => message;
}

abstract class BaseVideoExtractor {
  const BaseVideoExtractor();

  VideoPlatform get platform;

  /// Whether this extractor owns [url]. Defaults to matching the host against
  /// the platform table so the domain list lives in exactly one place.
  bool canHandle(String url) => UrlHelper.detectPlatform(url) == platform;

  Future<VideoMetadata> extract(String url, AppLocalizations l10n);
}
