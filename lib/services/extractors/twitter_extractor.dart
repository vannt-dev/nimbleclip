import 'dart:convert';

import '../../core/utils/http_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/url_helper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class TwitterExtractor extends BaseVideoExtractor {
  const TwitterExtractor();

  @override
  VideoPlatform get platform => VideoPlatform.twitter;

  static final RegExp _tweetIdPattern = RegExp(r'status(?:es)?/(\d+)');

  String? _extractTweetId(String url) =>
      _tweetIdPattern.firstMatch(url)?.group(1);

  @override
  Future<VideoMetadata> extract(String url, AppLocalizations l10n) async {
    var cleanUrl = url.trim();
    var tweetId = _extractTweetId(cleanUrl);

    // A t.co link carries no tweet id — it has to be expanded first.
    if (tweetId == null && UrlHelper.isShortLink(cleanUrl)) {
      cleanUrl = await ExtractorHttp.resolveRedirects(cleanUrl);
      tweetId = _extractTweetId(cleanUrl);
    }

    if (tweetId == null) {
      throw ExtractionException(l10n.xInvalidPost);
    }

    final viaFx = await _fromFxTwitter(tweetId, cleanUrl, l10n);
    if (viaFx != null) return viaFx;

    final viaVx = await _fromVxTwitter(tweetId, cleanUrl, l10n);
    if (viaVx != null) return viaVx;

    throw ExtractionException(l10n.xNoVideo);
  }

  Future<VideoMetadata?> _fromFxTwitter(
    String tweetId,
    String url,
    AppLocalizations l10n,
  ) async {
    final Map<String, dynamic> json;
    try {
      final response =
          await ExtractorHttp.get('https://api.fxtwitter.com/status/$tweetId');
      if (response.statusCode != 200) return null;
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    if (json['code'] != 200 || json['tweet'] == null) return null;
    final tweet = json['tweet'] as Map<String, dynamic>;
    final videos = (tweet['media'] as Map<String, dynamic>?)?['videos']
        as List<dynamic>?;
    if (videos == null || videos.isEmpty) return null;

    final video = videos.first as Map<String, dynamic>;
    final variants = (video['variants'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((v) => (v['content_type'] ?? '').toString().contains('mp4'))
        .toList();
    variants.sort((a, b) => ((b['bitrate'] as num?) ?? 0)
        .compareTo((a['bitrate'] as num?) ?? 0));

    final qualities = <VideoQualityOption>[];
    for (var i = 0; i < variants.length; i++) {
      final variant = variants[i];
      final variantUrl = variant['url']?.toString();
      if (variantUrl == null || variantUrl.isEmpty) continue;

      final kbps = (((variant['bitrate'] as num?) ?? 0) / 1000).round();
      // Twitter does not label variant resolution, but it is encoded in the CDN
      // path (`/vid/avc1/1280x720/`). Fall back to a bitrate estimate.
      final fromPath = RegExp(r'/(\d{2,4})x(\d{2,4})/').firstMatch(variantUrl);
      final quality = fromPath != null
          ? '${fromPath.group(2)}p'
          : _qualityFromBitrate(kbps);

      qualities.add(
        VideoQualityOption(
          id: 'x_${tweetId}_$i',
          label: '$quality ($kbps kbps)',
          quality: quality,
          format: 'mp4',
          downloadUrl: variantUrl,
        ),
      );
    }

    final directUrl = video['url']?.toString();
    if (qualities.isEmpty && directUrl != null && directUrl.isNotEmpty) {
      qualities.add(
        VideoQualityOption(
          id: 'x_${tweetId}_default',
          label: l10n.originalMp4,
          quality: 'Original',
          format: 'mp4',
          downloadUrl: directUrl,
        ),
      );
    }
    if (qualities.isEmpty) return null;

    final author = tweet['author'] as Map<String, dynamic>? ?? {};
    final text = tweet['text']?.toString().trim();
    final durationSec = (video['duration'] as num?)?.toInt();

    return VideoMetadata(
      id: tweetId,
      originalUrl: url,
      title: text != null && text.isNotEmpty
          ? text
          : l10n.xPostBy((author['screen_name'] ?? 'X').toString()),
      description: text,
      author: author['name']?.toString() ??
          author['screen_name']?.toString() ??
          'X User',
      authorAvatar: author['avatar_url']?.toString(),
      coverUrl: video['thumbnail_url']?.toString() ?? '',
      duration: durationSec != null && durationSec > 0
          ? Duration(seconds: durationSec)
          : null,
      platform: VideoPlatform.twitter,
      qualities: QualityHelper.sortedByQuality(qualities),
      viewCount: (tweet['views'] as num?)?.toInt(),
      likeCount: (tweet['likes'] as num?)?.toInt(),
      commentCount: (tweet['replies'] as num?)?.toInt(),
      shareCount: (tweet['retweets'] as num?)?.toInt(),
    );
  }

  Future<VideoMetadata?> _fromVxTwitter(
    String tweetId,
    String url,
    AppLocalizations l10n,
  ) async {
    final Map<String, dynamic> json;
    try {
      final response = await ExtractorHttp.get(
        'https://api.vxtwitter.com/Twitter/status/$tweetId',
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final videoUrls = (json['mediaURLs'] as List<dynamic>? ?? [])
        .map((u) => u.toString())
        .where((u) => u.contains('.mp4'))
        .toList();
    if (videoUrls.isEmpty) return null;

    final text = json['text']?.toString().trim();
    return VideoMetadata(
      id: tweetId,
      originalUrl: url,
      title: text != null && text.isNotEmpty ? text : 'X Video ($tweetId)',
      description: text,
      author: json['user_name']?.toString() ?? 'X User',
      coverUrl: '',
      platform: VideoPlatform.twitter,
      qualities: [
        VideoQualityOption(
          id: 'vx_$tweetId',
          label: l10n.originalMp4,
          quality: 'Original',
          format: 'mp4',
          downloadUrl: videoUrls.first,
        ),
      ],
      likeCount: (json['likes'] as num?)?.toInt(),
      commentCount: (json['replies'] as num?)?.toInt(),
      shareCount: (json['retweets'] as num?)?.toInt(),
    );
  }

  String _qualityFromBitrate(int kbps) {
    if (kbps > 1500) return '1080p';
    if (kbps > 800) return '720p';
    if (kbps > 400) return '480p';
    return '360p';
  }
}
