import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../core/utils/external_service_policy.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../core/utils/url_helper.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';
import 'facebook_fallback_client.dart';
import 'facebook_page_parser.dart';

class FacebookExtractor extends BaseVideoExtractor {
  final ExternalServiceAccess externalServiceAccess;
  final FacebookFallbackClient fallbackClient;
  static const _pageParser = FacebookPageParser();

  const FacebookExtractor({
    ExternalServiceAccess? externalServiceAccess,
    FacebookFallbackClient? fallbackClient,
  }) : externalServiceAccess =
           externalServiceAccess ?? const FixedExternalServiceAccess(true),
       fallbackClient = fallbackClient ?? const ToolspyFacebookFallbackClient();

  @override
  VideoPlatform get platform => VideoPlatform.facebook;

  // Facebook rotates which key carries the playable URL; try them in order of
  // how reliably each has carried a non-rate-limited stream.
  static final List<RegExp> _hdPatterns = [
    RegExp(r'"browser_native_hd_url"\s*:\s*"([^"]+)"'),
    RegExp(r'"hd_src_no_ratelimit"\s*:\s*"([^"]+)"'),
    RegExp(r'"playable_url_quality_hd"\s*:\s*"([^"]+)"'),
    RegExp(r'"hd_src"\s*:\s*"([^"]+)"'),
  ];

  static final List<RegExp> _sdPatterns = [
    RegExp(r'"browser_native_sd_url"\s*:\s*"([^"]+)"'),
    RegExp(r'"sd_src_no_ratelimit"\s*:\s*"([^"]+)"'),
    RegExp(r'"playable_url"\s*:\s*"([^"]+)"'),
    RegExp(r'"sd_src"\s*:\s*"([^"]+)"'),
  ];

  static final RegExp _facebookHost = RegExp(
    r'https?://(www\.|web\.|m\.)?facebook\.com',
  );
  // `_isPhotoUrl` runs once per candidate URL, so these three stay hoisted.
  static final RegExp _thumbnailCropParam = RegExp(
    r'(?:[?&]|&amp;)ctp=s(?:16|24|32|40|48|50|60|64)x',
  );
  static final RegExp _avatarBucket = RegExp(r'/t\d+(?:\.\d+)?-1/');
  static final RegExp _imageExtension = RegExp(r'\.(?:jpe?g|png|webp|gif)$');

  String? _firstMatch(String html, List<RegExp> patterns) {
    return _pageParser.firstMediaUrl(html, patterns);
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    var cleanUrl = url.trim();
    if (UrlHelper.isShortLink(cleanUrl)) {
      cleanUrl = await ExtractorHttp.resolveRedirects(cleanUrl);
    }

    VideoMetadata? imageFallback;

    VideoMetadata? accept(VideoMetadata? candidate) {
      if (candidate == null) return null;
      final hasVideo = candidate.qualities.any(
        (option) => !option.isImage && !option.isAudioOnly,
      );
      if (hasVideo) return candidate;
      final candidateImages = candidate.qualities
          .where((option) => option.isImage)
          .length;
      final fallbackImages =
          imageFallback?.qualities.where((option) => option.isImage).length ??
          0;
      if (imageFallback == null || candidateImages > fallbackImages) {
        imageFallback = candidate;
      }
      return null;
    }

    // Strategy 1: the watch page itself.
    var result = await _fromPage(cleanUrl, cleanUrl);
    final pageVideo = accept(result);
    if (pageVideo != null) {
      return _withPostPhotoFallback(pageVideo, cleanUrl);
    }

    // Strategy 2: the embed player. It serves a much smaller page that still
    // carries the playable URLs and is less likely to be gated behind a login
    // interstitial than the full watch page.
    final embedUrl =
        'https://www.facebook.com/plugins/video.php?href=${Uri.encodeComponent(cleanUrl)}';
    result = await _fromPage(embedUrl, cleanUrl);
    final embedVideo = accept(result);
    if (embedVideo != null) {
      return _withPostPhotoFallback(embedVideo, cleanUrl);
    }

    // Strategy 3: the mobile site, which renders a plainer document.
    final mobileUrl = cleanUrl.replaceFirst(
      _facebookHost,
      'https://m.facebook.com',
    );
    result = await _fromPage(
      mobileUrl,
      cleanUrl,

      userAgent: AppConstants.mobileUserAgent,
    );
    final mobileVideo = accept(result);
    if (mobileVideo != null) {
      return _withPostPhotoFallback(mobileVideo, cleanUrl);
    }

    if (imageFallback != null) {
      if (_isKnownVideoLink(cleanUrl)) {
        throw ExtractionException(
          const ExtractionFailure(ExtractionFailureKind.facebookNoVideo),
          diagnosticCode: 'facebook_video_not_exposed',
          attemptedStrategies: const ['page', 'embed', 'mobile'],
        );
      }
      return _withPostPhotoFallback(imageFallback!, cleanUrl);
    }

    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.facebookNoVideo),
      diagnosticCode: 'facebook_no_public_media',
      attemptedStrategies: const ['page', 'embed', 'mobile'],
    );
  }

  bool _isKnownVideoLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/share/r/') ||
        path.startsWith('/share/v/') ||
        path.startsWith('/reel/') ||
        path.startsWith('/reels/') ||
        path.contains('/videos/') ||
        path == '/watch/' ||
        path == '/watch';
  }

  /// Facebook's anonymous mobile document often exposes only the first Open
  /// Graph image of a gallery. For public post permalinks, use a narrowly
  /// scoped extractor fallback when the Relay payload did not reveal the set.
  /// A failure here is non-fatal: the directly extracted media remains usable.
  Future<VideoMetadata> _withPostPhotoFallback(
    VideoMetadata metadata,
    String postUrl,
  ) async {
    final uri = Uri.tryParse(postUrl);
    final isPostPermalink =
        uri != null &&
        (uri.path.contains('/posts/') ||
            uri.path.endsWith('/permalink.php') ||
            uri.path.endsWith('/story.php'));
    final currentImages = metadata.qualities
        .where((option) => option.isImage)
        .toList();
    if (!isPostPermalink ||
        currentImages.length > 1 ||
        !externalServiceAccess.allowExternalServices) {
      return metadata;
    }

    // Fixture tests that only override GET must never leak into live network.
    if (ExtractorHttp.isUsingOverrides && !ExtractorHttp.hasPostOverride) {
      return metadata;
    }

    try {
      final rawImages = await fallbackClient.extractImageUrls(postUrl);

      final fallbackImages = <String>[];
      final identities = <String>{};
      for (final value in rawImages) {
        final imageUrl = decodeHtmlEntities(value.toString());
        if (!_isPostPhoto(imageUrl)) continue;
        final identity = _photoIdentity(imageUrl);
        if (identity.isEmpty || !identities.add(identity)) continue;
        fallbackImages.add(imageUrl);
      }
      if (fallbackImages.length <= currentImages.length) return metadata;

      final nonImages = metadata.qualities
          .where((option) => !option.isImage)
          .toList();
      final images = <VideoQualityOption>[
        for (var index = 0; index < fallbackImages.length; index++)
          VideoQualityOption.image(
            id: 'fb_image_${index + 1}_${metadata.id}',
            mediaId: 'fb_image_${index + 1}_${metadata.id}',
            label: ImageIndex(index + 1),
            quality: 'Original',
            format: MediaFormatHelper.inferImageFormat(fallbackImages[index]),
            downloadUrl: fallbackImages[index],
          ),
      ];

      return VideoMetadata(
        id: metadata.id,
        originalUrl: metadata.originalUrl,
        title: metadata.title,
        description: metadata.description,
        author: metadata.author,
        authorAvatar: metadata.authorAvatar,
        coverUrl: fallbackImages.first,
        duration: metadata.duration,
        platform: metadata.platform,
        qualities: QualityHelper.sortedByQuality([...nonImages, ...images]),
        viewCount: metadata.viewCount,
        likeCount: metadata.likeCount,
        commentCount: metadata.commentCount,
        shareCount: metadata.shareCount,
      );
    } catch (_) {
      return metadata;
    }
  }

  bool _isPostPhoto(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (!host.endsWith('fbcdn.net')) return false;

    final lower = url.toLowerCase();
    if (lower.contains('external-') ||
        lower.contains('safe_image.php') ||
        _thumbnailCropParam.hasMatch(lower)) {
      return false;
    }

    // Facebook reserves the `-1` CDN buckets for profile/avatar images. Post
    // photos use content buckets such as t39.30808-6 and t1.6435-9.
    final path = uri.path.toLowerCase();
    if (_avatarBucket.hasMatch(path)) {
      return false;
    }
    return _imageExtension.hasMatch(path);
  }

  String _photoIdentity(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return path.isEmpty ? '' : path.split('/').last.toLowerCase();
  }

  Future<VideoMetadata?> _fromPage(
    String pageUrl,
    String originalUrl, {
    String userAgent = AppConstants.defaultUserAgent,
  }) async {
    final String html;
    try {
      final response = await ExtractorHttp.get(pageUrl, userAgent: userAgent);
      if (response.statusCode >= 400) return null;
      html = response.body;
    } catch (_) {
      return null;
    }

    final hdUrl = _firstMatch(html, _hdPatterns);
    final sdUrl = _firstMatch(html, _sdPatterns);
    final openGraphVideo = _pageParser.openGraphVideo(html);
    final openGraphVideoUrl = openGraphVideo == null
        ? null
        : Uri.parse(pageUrl).resolve(openGraphVideo).toString();
    final thumbnailUrl = _thumbnail(html);
    final photoUrls = await _pageParser.photoUrlsAsync(html);
    if (photoUrls.isEmpty &&
        hdUrl == null &&
        sdUrl == null &&
        openGraphVideoUrl == null) {
      if (thumbnailUrl == null) return null;
      photoUrls.add(thumbnailUrl);
    }

    final id =
        _videoId(html) ?? DateTime.now().millisecondsSinceEpoch.toString();
    final qualities = <VideoQualityOption>[
      if (hdUrl != null)
        VideoQualityOption.video(
          id: 'fb_hd_$id',
          mediaId: 'fb_video_$id',
          label: const Hd720(),
          quality: 'HD 720p',
          format: 'mp4',
          downloadUrl: hdUrl,
        ),
      if (sdUrl != null && sdUrl != hdUrl)
        VideoQualityOption.video(
          id: 'fb_sd_$id',
          mediaId: 'fb_video_$id',
          label: const Sd480(),
          quality: 'SD 480p',
          format: 'mp4',
          downloadUrl: sdUrl,
        ),
      if (hdUrl == null && sdUrl == null && openGraphVideoUrl != null)
        VideoQualityOption.video(
          id: 'fb_original_$id',
          mediaId: 'fb_video_$id',
          label: const OriginalVideo(),
          quality: 'Original',
          format: 'mp4',
          downloadUrl: openGraphVideoUrl,
        ),
      for (var index = 0; index < photoUrls.length; index++)
        VideoQualityOption.image(
          id: 'fb_image_${index + 1}_$id',
          mediaId: 'fb_image_${index + 1}_$id',
          label: ImageIndex(index + 1),
          quality: 'Original',
          format: MediaFormatHelper.inferImageFormat(photoUrls[index]),
          downloadUrl: photoUrls[index],
        ),
    ];

    return VideoMetadata(
      id: id,
      originalUrl: originalUrl,
      title: _title(html),
      description: _stringField(html, 'message') ?? _stringField(html, 'title'),
      author: _owner(html) ?? 'Facebook',
      coverUrl: photoUrls.firstOrNull ?? thumbnailUrl ?? '',
      duration: _duration(html),
      platform: VideoPlatform.facebook,
      qualities: QualityHelper.sortedByQuality(qualities),
    );
  }

  String? _videoId(String html) => _pageParser.videoId(html);

  String _title(String html) {
    return _pageParser.title(html);
  }

  String? _stringField(String html, String key) {
    return _pageParser.stringField(html, key);
  }

  String? _owner(String html) {
    return _pageParser.owner(html);
  }

  String? _thumbnail(String html) {
    return _pageParser.thumbnail(html);
  }

  Duration? _duration(String html) {
    return _pageParser.duration(html);
  }
}
