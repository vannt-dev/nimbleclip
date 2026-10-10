import '../../core/utils/external_service_policy.dart';
import '../../core/utils/url_helper.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';
import 'generic_extractor.dart';

/// The extractors of the public core: one, which reads a link to a media file
/// or to a page that names its media in the usual metadata.
///
/// The sites NimbleClip knows by name (YouTube, TikTok, Facebook and the
/// others) are read by the full core, which is not part of this repository.
/// A link to one of them is answered with "no downloadable media" here.
class ExtractorRegistry {
  // The full core hands this to the extractors that may call other services.
  // ignore: avoid_unused_constructor_parameters
  ExtractorRegistry({ExternalServiceAccess? externalServiceAccess})
    : extractors = const [GenericExtractor()];

  /// GenericExtractor must stay last: its `canHandle` accepts everything.
  final List<BaseVideoExtractor> extractors;

  BaseVideoExtractor getExtractorFor(String url) {
    for (final extractor in extractors) {
      if (extractor.canHandle(url)) return extractor;
    }
    return const GenericExtractor();
  }

  Future<VideoMetadata> extract(String rawUrl) async {
    final cleanUrl = UrlHelper.extractCleanUrl(rawUrl);
    if (!UrlHelper.isValidVideoUrl(cleanUrl)) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.invalidLink),
      );
    }

    // A site NimbleClip knows by name is read by the full core. Treated as
    // any other page it would offer its poster picture as the download, which
    // is not what a link to a video is asked for.
    if (UrlHelper.detectPlatform(cleanUrl) != VideoPlatform.generic) {
      throw ExtractionException(
        const ExtractionFailure(
          ExtractionFailureKind.noDownloadStreams,
          detail: 'this site needs the full core',
        ),
        diagnosticCode: 'public_core',
      );
    }

    final metadata = await getExtractorFor(cleanUrl).extract(cleanUrl);
    if (metadata.qualities.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.noDownloadStreams),
      );
    }
    return metadata;
  }
}
