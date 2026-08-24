import 'dart:convert';

import '../../core/utils/http_helper.dart';
import '../../core/utils/external_service_policy.dart';
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

    if (!ExternalServicePolicy.allowExternalServices) {
      throw ExtractionException(l10n.externalServicesDisabled);
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
      final response = await ExtractorHttp.getWithRetry(
        'https://api.fxtwitter.com/status/$tweetId',
        service: 'FxTwitter',
      );
      if (response.statusCode != 200) return null;
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    if (json['code'] != 200 || json['tweet'] == null) return null;
    final tweet = json['tweet'] as Map<String, dynamic>;
    final media = tweet['media'] as Map<String, dynamic>? ?? const {};
    final videos = (media['videos'] as List<dynamic>? ?? const []);
    final photos = (media['photos'] as List<dynamic>? ?? const []);
    final qualities = <VideoQualityOption>[];
    for (var videoIndex = 0; videoIndex < videos.length; videoIndex++) {
      final video = videos[videoIndex];
      if (video is! Map<String, dynamic>) continue;
      final variants =
          (video['variants'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .where(
                (v) => (v['content_type'] ?? '').toString().contains('mp4'),
              )
              .toList()
            ..sort(
              (a, b) => ((b['bitrate'] as num?) ?? 0).compareTo(
                (a['bitrate'] as num?) ?? 0,
              ),
            );

      for (
        var variantIndex = 0;
        variantIndex < variants.length;
        variantIndex++
      ) {
        final variant = variants[variantIndex];
        final variantUrl = variant['url']?.toString();
        if (variantUrl == null || variantUrl.isEmpty) continue;
        final kbps = (((variant['bitrate'] as num?) ?? 0) / 1000).round();
        final fromPath = RegExp(
          r'/(\d{2,4})x(\d{2,4})/',
        ).firstMatch(variantUrl);
        final quality = fromPath != null
            ? '${fromPath.group(2)}p'
            : _qualityFromBitrate(kbps);
        qualities.add(
          VideoQualityOption(
            id: 'x_${tweetId}_${videoIndex}_$variantIndex',
            mediaId: 'x_video_${tweetId}_$videoIndex',
            label: '$quality ($kbps kbps)',
            quality: quality,
            format: 'mp4',
            downloadUrl: variantUrl,
          ),
        );
      }

      final directUrl = video['url']?.toString();
      if (!qualities.any(
            (option) => option.mediaId == 'x_video_${tweetId}_$videoIndex',
          ) &&
          directUrl != null &&
          directUrl.isNotEmpty) {
        qualities.add(
          VideoQualityOption(
            id: 'x_${tweetId}_${videoIndex}_default',
            mediaId: 'x_video_${tweetId}_$videoIndex',
            label: l10n.originalMp4,
            quality: 'Original',
            format: 'mp4',
            downloadUrl: directUrl,
          ),
        );
      }
    }

    for (var photoIndex = 0; photoIndex < photos.length; photoIndex++) {
      final photo = photos[photoIndex];
      if (photo is! Map<String, dynamic>) continue;
      final photoUrl = photo['url']?.toString();
      if (photoUrl == null || photoUrl.isEmpty) continue;
      qualities.add(
        VideoQualityOption(
          id: 'x_image_${tweetId}_$photoIndex',
          mediaId: 'x_image_${tweetId}_$photoIndex',
          label: l10n.imageLabel(photoIndex + 1),
          quality: 'Original',
          format: _imageFormat(photoUrl, photo['format']?.toString()),
          downloadUrl: photoUrl,
          kind: MediaKind.image,
        ),
      );
    }
    if (qualities.isEmpty) return null;

    final author = tweet['author'] as Map<String, dynamic>? ?? {};
    final text = tweet['text']?.toString().trim();
    final firstVideo = videos.whereType<Map<String, dynamic>>().firstOrNull;
    final firstPhoto = photos.whereType<Map<String, dynamic>>().firstOrNull;
    final durationSec = (firstVideo?['duration'] as num?)?.toInt();

    return VideoMetadata(
      id: tweetId,
      originalUrl: url,
      title: text != null && text.isNotEmpty
          ? text
          : l10n.xPostBy((author['screen_name'] ?? 'X').toString()),
      description: text,
      author:
          author['name']?.toString() ??
          author['screen_name']?.toString() ??
          'X User',
      authorAvatar: author['avatar_url']?.toString(),
      coverUrl:
          firstVideo?['thumbnail_url']?.toString() ??
          firstPhoto?['url']?.toString() ??
          '',
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
      final response = await ExtractorHttp.getWithRetry(
        'https://api.vxtwitter.com/Twitter/status/$tweetId',
        service: 'VxTwitter',
        timeout: const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final mediaUrls = (json['mediaURLs'] as List<dynamic>? ?? [])
        .map((u) => u.toString())
        .where((u) => u.startsWith('http'))
        .toList();
    if (mediaUrls.isEmpty) return null;

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
        for (var index = 0; index < mediaUrls.length; index++)
          VideoQualityOption(
            id: 'vx_${tweetId}_$index',
            mediaId: 'vx_media_${tweetId}_$index',
            label: _isImageUrl(mediaUrls[index])
                ? l10n.imageLabel(index + 1)
                : l10n.originalMp4,
            quality: 'Original',
            format: _isImageUrl(mediaUrls[index])
                ? _imageFormat(mediaUrls[index], null)
                : 'mp4',
            downloadUrl: mediaUrls[index],
            kind: _isImageUrl(mediaUrls[index])
                ? MediaKind.image
                : MediaKind.video,
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

  bool _isImageUrl(String url) => RegExp(
    r'\.(?:jpe?g|png|gif|webp|avif)(?:$|[?#])',
    caseSensitive: false,
  ).hasMatch(url);

  String _imageFormat(String url, String? declared) {
    final normalized = declared?.toLowerCase();
    if (normalized == 'jpeg') return 'jpg';
    if (normalized != null &&
        const {'jpg', 'png', 'gif', 'webp', 'avif'}.contains(normalized)) {
      return normalized;
    }
    final match = RegExp(r'\.([a-zA-Z0-9]+)(?:$|[?#])').firstMatch(url);
    final extension = match?.group(1)?.toLowerCase();
    return extension == 'jpeg' ? 'jpg' : extension ?? 'jpg';
  }
}
