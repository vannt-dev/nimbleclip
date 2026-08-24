import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../core/utils/media_url_helper.dart';
import '../../core/utils/external_service_policy.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../core/utils/url_helper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

class FacebookExtractor extends BaseVideoExtractor {
  const FacebookExtractor();

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

  String? _firstMatch(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) {
        final decoded = MediaUrlHelper.decode(value);
        if (MediaUrlHelper.isHttp(decoded)) return decoded;
      }
    }
    return null;
  }

  @override
  Future<VideoMetadata> extract(String url, AppLocalizations l10n) async {
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
    var result = await _fromPage(cleanUrl, cleanUrl, l10n);
    final pageVideo = accept(result);
    if (pageVideo != null) {
      return _withPostPhotoFallback(pageVideo, cleanUrl, l10n);
    }

    // Strategy 2: the embed player. It serves a much smaller page that still
    // carries the playable URLs and is less likely to be gated behind a login
    // interstitial than the full watch page.
    final embedUrl =
        'https://www.facebook.com/plugins/video.php?href=${Uri.encodeComponent(cleanUrl)}';
    result = await _fromPage(embedUrl, cleanUrl, l10n);
    final embedVideo = accept(result);
    if (embedVideo != null) {
      return _withPostPhotoFallback(embedVideo, cleanUrl, l10n);
    }

    // Strategy 3: the mobile site, which renders a plainer document.
    final mobileUrl = cleanUrl.replaceFirst(
      RegExp(r'https?://(www\.|web\.|m\.)?facebook\.com'),
      'https://m.facebook.com',
    );
    result = await _fromPage(
      mobileUrl,
      cleanUrl,
      l10n,
      userAgent: AppConstants.mobileUserAgent,
    );
    final mobileVideo = accept(result);
    if (mobileVideo != null) {
      return _withPostPhotoFallback(mobileVideo, cleanUrl, l10n);
    }

    if (imageFallback != null) {
      return _withPostPhotoFallback(imageFallback!, cleanUrl, l10n);
    }

    throw ExtractionException(l10n.facebookNoVideo);
  }

  /// Facebook's anonymous mobile document often exposes only the first Open
  /// Graph image of a gallery. For public post permalinks, use a narrowly
  /// scoped extractor fallback when the Relay payload did not reveal the set.
  /// A failure here is non-fatal: the directly extracted media remains usable.
  Future<VideoMetadata> _withPostPhotoFallback(
    VideoMetadata metadata,
    String postUrl,
    AppLocalizations l10n,
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
        !ExternalServicePolicy.allowExternalServices) {
      return metadata;
    }

    // Fixture tests that only override GET must never leak into live network.
    if (ExtractorHttp.isUsingOverrides && !ExtractorHttp.hasPostOverride) {
      return metadata;
    }

    try {
      final response = await ExtractorHttp.postWithRetry(
        'https://toolspy.net/api/facebook-image-extract/',
        service: 'Toolspy',
        body: jsonEncode({'url': postUrl}),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return metadata;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return metadata;
      final rawImages = payload['images'];
      if (rawImages is! List) return metadata;

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
            label: l10n.imageLabel(index + 1),
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
        RegExp(
          r'(?:[?&]|&amp;)ctp=s(?:16|24|32|40|48|50|60|64)x',
        ).hasMatch(lower)) {
      return false;
    }

    // Facebook reserves the `-1` CDN buckets for profile/avatar images. Post
    // photos use content buckets such as t39.30808-6 and t1.6435-9.
    if (RegExp(r'/t\d+(?:\.\d+)?-1/').hasMatch(uri.path.toLowerCase())) {
      return false;
    }
    return RegExp(
      r'\.(?:jpe?g|png|webp|gif)$',
    ).hasMatch(uri.path.toLowerCase());
  }

  String _photoIdentity(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    return path.isEmpty ? '' : path.split('/').last.toLowerCase();
  }

  Future<VideoMetadata?> _fromPage(
    String pageUrl,
    String originalUrl,
    AppLocalizations l10n, {
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
    final thumbnailUrl = _thumbnail(html);
    final photoUrls = _extractPhotoUrls(html);
    if (photoUrls.isEmpty && hdUrl == null && sdUrl == null) {
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
          label: l10n.highQuality720,
          quality: 'HD 720p',
          format: 'mp4',
          downloadUrl: hdUrl,
        ),
      if (sdUrl != null && sdUrl != hdUrl)
        VideoQualityOption.video(
          id: 'fb_sd_$id',
          mediaId: 'fb_video_$id',
          label: l10n.standardQuality480,
          quality: 'SD 480p',
          format: 'mp4',
          downloadUrl: sdUrl,
        ),
      for (var index = 0; index < photoUrls.length; index++)
        VideoQualityOption.image(
          id: 'fb_image_${index + 1}_$id',
          mediaId: 'fb_image_${index + 1}_$id',
          label: l10n.imageLabel(index + 1),
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

  String? _videoId(String html) =>
      RegExp(r'"video_id"\s*:\s*"(\d+)"').firstMatch(html)?.group(1) ??
      RegExp(r'"videoId"\s*:\s*"(\d+)"').firstMatch(html)?.group(1);

  String _title(String html) {
    final ogTitle = RegExp(
      r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"',
    ).firstMatch(html)?.group(1);
    final rawTitle =
        ogTitle ??
        RegExp(
          r'<title[^>]*>(.*?)</title>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(html)?.group(1);
    if (rawTitle == null || rawTitle.trim().isEmpty) return 'Facebook Video';

    final title = decodeHtmlEntities(
      decodeJsonEscapes(rawTitle),
    ).replaceAll(RegExp(r'\s*\|\s*Facebook\s*$'), '').trim();
    return title.isEmpty ? 'Facebook Video' : title;
  }

  String? _stringField(String html, String key) {
    final value = RegExp('"$key":"([^"]{1,400})"').firstMatch(html)?.group(1);
    return value == null ? null : decodeJsonEscapes(value);
  }

  String? _owner(String html) {
    final owner =
        RegExp(r'"owner":\{[^}]*"name":"([^"]+)"').firstMatch(html)?.group(1) ??
        RegExp(r'"ownerName":"([^"]+)"').firstMatch(html)?.group(1);
    return owner == null ? null : decodeJsonEscapes(owner);
  }

  String? _thumbnail(String html) {
    final raw =
        RegExp(
          r'"preferred_thumbnail":\{"image":\{"uri":"([^"]+)"',
        ).firstMatch(html)?.group(1) ??
        RegExp(
          r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
        ).firstMatch(html)?.group(1);
    return raw == null ? null : MediaUrlHelper.decode(raw);
  }

  Duration? _duration(String html) {
    final ms = RegExp(
      r'"playable_duration_in_ms":(\d+)',
    ).firstMatch(html)?.group(1);
    if (ms != null) {
      final value = int.tryParse(ms);
      if (value != null && value > 0) return Duration(milliseconds: value);
    }
    final seconds = RegExp(
      r'"video_duration":(\d+)',
    ).firstMatch(html)?.group(1);
    final value = int.tryParse(seconds ?? '');
    return value != null && value > 0 ? Duration(seconds: value) : null;
  }

  /// Extracts post photos from Facebook's public Relay payload. Multi-photo
  /// posts are represented by `all_subattachments`; single photo pages expose
  /// a `Photo` node. Restricting collection to those structures avoids pulling
  /// avatars, reaction icons and the poster image of a video into the batch.
  List<String> _extractPhotoUrls(String html) {
    final urls = <String>[];

    void addPhotoNode(dynamic value) {
      if (value is! Map<String, dynamic>) return;
      final candidates = <({String url, int area})>[];

      void findImages(dynamic node, {bool insideImageField = false}) {
        if (node is Map<String, dynamic>) {
          final uri = node['uri']?.toString() ?? node['url']?.toString();
          if (insideImageField && uri != null && MediaUrlHelper.isHttp(uri)) {
            final width = (node['width'] as num?)?.toInt() ?? 0;
            final height = (node['height'] as num?)?.toInt() ?? 0;
            candidates.add((url: decodeJsonEscapes(uri), area: width * height));
          }
          for (final entry in node.entries) {
            final key = entry.key.toLowerCase();
            findImages(
              entry.value,
              insideImageField:
                  insideImageField ||
                  key == 'image' ||
                  key.endsWith('_image') ||
                  key.endsWith('image'),
            );
          }
        } else if (node is List) {
          for (final child in node) {
            findImages(child, insideImageField: insideImageField);
          }
        }
      }

      findImages(value);
      if (candidates.isEmpty) return;
      candidates.sort((a, b) => b.area.compareTo(a.area));
      final best = candidates.first.url;
      if (!urls.contains(best)) urls.add(best);
    }

    void visit(dynamic value, {bool inSubattachments = false}) {
      if (value is Map<String, dynamic>) {
        final type = value['__typename']?.toString();
        if (type == 'Photo') {
          addPhotoNode(value);
        } else if (inSubattachments && value['media'] != null) {
          addPhotoNode(value['media']);
        }

        for (final entry in value.entries) {
          final isSubattachments =
              inSubattachments || entry.key == 'all_subattachments';
          visit(entry.value, inSubattachments: isSubattachments);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child, inSubattachments: inSubattachments);
        }
      }
    }

    final scripts = RegExp(
      r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
      caseSensitive: false,
    ).allMatches(html);
    for (final script in scripts) {
      try {
        visit(jsonDecode(decodeHtmlEntities(script.group(1) ?? '')));
      } catch (_) {
        // Facebook may mix non-JSON bootloader scripts into the page. Other
        // payloads and the Open Graph fallback can still provide the media.
      }
    }
    return urls;
  }
}
