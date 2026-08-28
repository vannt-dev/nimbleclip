import '../../core/utils/url_helper.dart';
import '../../models/video_metadata.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';
import 'facebook_extractor.dart';
import 'generic_extractor.dart';
import 'instagram_extractor.dart';
import 'tiktok_extractor.dart';
import 'twitter_extractor.dart';
import 'youtube_extractor.dart';
import '../../core/utils/external_service_policy.dart';

class ExtractorRegistry {
  ExtractorRegistry({ExternalServiceAccess? externalServiceAccess})
    : extractors = [
        const YouTubeExtractor(),
        TikTokExtractor(externalServiceAccess: externalServiceAccess),
        TwitterExtractor(externalServiceAccess: externalServiceAccess),
        FacebookExtractor(externalServiceAccess: externalServiceAccess),
        InstagramExtractor(externalServiceAccess: externalServiceAccess),
        const GenericExtractor(),
      ];

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

    final metadata = await getExtractorFor(cleanUrl).extract(cleanUrl);
    if (metadata.qualities.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.noDownloadStreams),
      );
    }
    return metadata;
  }
}
