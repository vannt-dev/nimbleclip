import '../../core/utils/url_helper.dart';
import '../../models/video_metadata.dart';
import 'base_extractor.dart';
import 'facebook_extractor.dart';
import 'generic_extractor.dart';
import 'instagram_extractor.dart';
import 'tiktok_extractor.dart';
import 'twitter_extractor.dart';
import 'youtube_extractor.dart';

class ExtractorRegistry {
  /// GenericExtractor must stay last: its `canHandle` accepts everything.
  static const List<BaseVideoExtractor> extractors = [
    YouTubeExtractor(),
    TikTokExtractor(),
    TwitterExtractor(),
    FacebookExtractor(),
    InstagramExtractor(),
    GenericExtractor(),
  ];

  static BaseVideoExtractor getExtractorFor(String url) {
    for (final extractor in extractors) {
      if (extractor.canHandle(url)) return extractor;
    }
    return const GenericExtractor();
  }

  static Future<VideoMetadata> extract(String rawUrl) async {
    final cleanUrl = UrlHelper.extractCleanUrl(rawUrl);
    if (!UrlHelper.isValidVideoUrl(cleanUrl)) {
      throw const ExtractionException(
        'Đường dẫn không hợp lệ. Hãy nhập một liên kết video http/https.',
      );
    }

    final metadata = await getExtractorFor(cleanUrl).extract(cleanUrl);
    if (metadata.qualities.isEmpty) {
      throw const ExtractionException(
        'Không tìm thấy luồng tải nào cho liên kết này.',
      );
    }
    return metadata;
  }
}
