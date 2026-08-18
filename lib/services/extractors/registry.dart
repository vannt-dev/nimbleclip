import '../../models/video_metadata.dart';
import '../../core/utils/url_helper.dart';
import 'base_extractor.dart';
import 'facebook_extractor.dart';
import 'generic_extractor.dart';
import 'tiktok_extractor.dart';
import 'twitter_extractor.dart';
import 'youtube_extractor.dart';

class ExtractorRegistry {
  static final List<BaseVideoExtractor> _extractors = [
    YouTubeExtractor(),
    TikTokExtractor(),
    TwitterExtractor(),
    FacebookExtractor(),
    GenericExtractor(), // Must be last as fallback
  ];

  static BaseVideoExtractor getExtractorFor(String url) {
    for (final extractor in _extractors) {
      if (extractor.canHandle(url)) {
        return extractor;
      }
    }
    return GenericExtractor();
  }

  static Future<VideoMetadata> extract(String rawUrl) async {
    final cleanUrl = UrlHelper.extractCleanUrl(rawUrl);
    if (!UrlHelper.isValidVideoUrl(cleanUrl)) {
      throw Exception('Invalid URL. Please enter a valid video link (http/https).');
    }

    final extractor = getExtractorFor(cleanUrl);
    return await extractor.extract(cleanUrl);
  }
}
