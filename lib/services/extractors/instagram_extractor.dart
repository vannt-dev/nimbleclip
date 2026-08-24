import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/external_service_policy.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../core/utils/url_helper.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

/// Instagram extractor for public Reels and feed videos.
///
/// Instagram gates most content behind a login wall and rotates its internal
/// endpoints frequently, so this works on a best-effort basis: the embed page is
/// tried first because it is the only surface that still renders without a
/// session for public posts. When every strategy fails the user is told plainly
/// that the post needs a login rather than being handed a broken download.
class InstagramExtractor extends BaseVideoExtractor {
  const InstagramExtractor();

  static String? _snapInstaExpiry;
  static String? _snapInstaToken;

  @override
  VideoPlatform get platform => VideoPlatform.instagram;

  static final RegExp _shortcodePattern = RegExp(
    r'/(?:reels?|p|tv)/([A-Za-z0-9_-]+)',
  );

  String? _extractShortcode(String url) =>
      _shortcodePattern.firstMatch(url)?.group(1);

  @override
  Future<VideoMetadata> extract(String url, AppLocalizations l10n) async {
    var cleanUrl = url.trim();
    var shortcode = _extractShortcode(cleanUrl);

    if (shortcode == null && UrlHelper.isShortLink(cleanUrl)) {
      cleanUrl = await ExtractorHttp.resolveRedirects(cleanUrl);
      shortcode = _extractShortcode(cleanUrl);
    }

    if (shortcode == null) {
      throw ExtractionException(l10n.instagramInvalidPost);
    }

    final viaEmbed = await _fromEmbedPage(shortcode, cleanUrl, l10n);
    if (viaEmbed != null) {
      return await _enrichImagePost(viaEmbed, shortcode, cleanUrl, l10n);
    }

    final viaPage = await _fromPostPage(shortcode, cleanUrl, l10n);
    if (viaPage != null) {
      return await _enrichImagePost(viaPage, shortcode, cleanUrl, l10n);
    }

    final viaSnapInsta = await _fromSnapInsta(shortcode, cleanUrl, l10n);
    if (viaSnapInsta != null) return viaSnapInsta;

    throw ExtractionException(l10n.instagramLoginRequired);
  }

  Future<VideoMetadata> _enrichImagePost(
    VideoMetadata metadata,
    String shortcode,
    String url,
    AppLocalizations l10n,
  ) async {
    final images = metadata.qualities.where((option) => option.isImage);
    if (images.length != 1) return metadata;
    return await _fromSnapInsta(shortcode, url, l10n, fallback: metadata) ??
        metadata;
  }

  /// SnapInsta exposes carousel slides that Instagram omits from anonymous
  /// post HTML. Its search token is read from the public landing page for each
  /// request instead of being persisted because the token is time-limited.
  Future<VideoMetadata?> _fromSnapInsta(
    String shortcode,
    String url,
    AppLocalizations l10n, {
    VideoMetadata? fallback,
  }) async {
    if (!ExternalServicePolicy.allowExternalServices) return fallback;
    try {
      var expiry = _snapInstaExpiry;
      var token = _snapInstaToken;
      final expirySeconds = int.tryParse(expiry ?? '');
      final cacheValid =
          !ExtractorHttp.isUsingOverrides &&
          expirySeconds != null &&
          expirySeconds > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30 &&
          token != null;
      if (!cacheValid) {
        final landing = await ExtractorHttp.getWithRetry(
          'https://snap-insta.to/vi',
          service: 'SnapInsta',
          userAgent: AppConstants.defaultUserAgent,
        );
        if (landing.statusCode != 200) return null;
        expiry = RegExp(
          r'\bk_exp\s*=\s*"([^"]+)"',
        ).firstMatch(landing.body)?.group(1);
        token = RegExp(
          r'\bk_token\s*=\s*"([^"]+)"',
        ).firstMatch(landing.body)?.group(1);
        if (!ExtractorHttp.isUsingOverrides) {
          _snapInstaExpiry = expiry;
          _snapInstaToken = token;
        }
      }
      if (expiry == null || token == null) return null;

      final response = await ExtractorHttp.postWithRetry(
        'https://snap-insta.to/api/ajaxSearch',
        service: 'SnapInsta',
        userAgent: AppConstants.defaultUserAgent,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: {
          'k_exp': expiry,
          'k_token': token,
          'q': url,
          't': 'media',
          'lang': 'vi',
          'v': 'v2',
        },
      );
      if (response.statusCode != 200) return null;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['status'] != 'ok') return null;
      final resultHtml = payload['data']?.toString() ?? '';
      if (resultHtml.isEmpty) return null;

      final downloadUrls = <String>[];
      final previewUrls = <String>[];
      final mediaKinds = <MediaKind>[];
      final sourcePath = Uri.tryParse(url)?.path.toLowerCase() ?? '';
      final sourceIsVideo =
          sourcePath.contains('/reel/') ||
          sourcePath.contains('/reels/') ||
          sourcePath.contains('/tv/');
      for (final match in RegExp(
        r'<li[^>]*>([\s\S]*?)</li>',
        caseSensitive: false,
      ).allMatches(resultHtml)) {
        final item = match.group(1) ?? '';
        final preview = _firstGroup(item, [
          RegExp(r'<img[^>]+data-src="([^"]+)"', caseSensitive: false),
          RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false),
        ]);
        final itemLooksVideo = RegExp(
          r'icon-dlvideo|<video|(?:type|media)[-_ ]?video|download[-_ ]?video',
          caseSensitive: false,
        ).hasMatch(item);
        final videoDownload = itemLooksVideo
            ? _firstGroup(item, [
                RegExp(
                  r'<a[^>]*title="[^"]*video"[^>]*href="(https://dl\.snapcdn\.app/get\?[^"]+)"[^>]*>',
                  caseSensitive: false,
                ),
                RegExp(
                  r'<a[^>]+href="(https://dl\.snapcdn\.app/get\?[^"]+)"[^>]*>[\s\S]*?(?:Tải|Download)[^<]*video',
                  caseSensitive: false,
                ),
              ])
            : null;
        final download =
            videoDownload ??
            _firstGroup(item, [
              RegExp(r'<option[^>]+value="([^"]+)"', caseSensitive: false),
              RegExp(
                r'<a[^>]+href="(https://dl\.snapcdn\.app/get\?[^"]+)"',
                caseSensitive: false,
              ),
            ]);
        if (download == null || preview == null) continue;

        final cleanDownload = decodeHtmlEntities(download);
        final cleanPreview = decodeHtmlEntities(preview);
        final downloadUri = Uri.tryParse(cleanDownload);
        final previewUri = Uri.tryParse(cleanPreview);
        if (downloadUri?.scheme != 'https' ||
            downloadUri?.host != 'dl.snapcdn.app' ||
            previewUri?.scheme != 'https' ||
            previewUri?.host != 'i.snapcdn.app' ||
            downloadUrls.contains(cleanDownload)) {
          continue;
        }
        downloadUrls.add(cleanDownload);
        previewUrls.add(cleanPreview);
        mediaKinds.add(
          sourceIsVideo || itemLooksVideo ? MediaKind.video : MediaKind.image,
        );
      }
      if (downloadUrls.isEmpty) return null;

      return VideoMetadata(
        id: shortcode,
        originalUrl: url,
        title: fallback?.title ?? 'Instagram Post ($shortcode)',
        description: fallback?.description,
        author: fallback?.author ?? 'Instagram',
        authorAvatar: fallback?.authorAvatar,
        coverUrl: previewUrls.first,
        platform: VideoPlatform.instagram,
        qualities: [
          for (var index = 0; index < downloadUrls.length; index++)
            VideoQualityOption(
              id: mediaKinds[index] == MediaKind.video
                  ? 'ig_video_${index + 1}_$shortcode'
                  : 'ig_image_${index + 1}_$shortcode',
              mediaId: mediaKinds[index] == MediaKind.video
                  ? 'ig_video_${index + 1}_$shortcode'
                  : 'ig_image_${index + 1}_$shortcode',
              label: mediaKinds[index] == MediaKind.video
                  ? l10n.originalMp4
                  : l10n.imageLabel(index + 1),
              quality: mediaKinds[index] == MediaKind.video
                  ? 'Original'
                  : l10n.imageLabel(index + 1),
              format: mediaKinds[index] == MediaKind.video ? 'mp4' : 'jpg',
              downloadUrl: downloadUrls[index],
              thumbnailUrl: previewUrls[index],
              kind: mediaKinds[index],
            ),
        ],
        viewCount: fallback?.viewCount,
        likeCount: fallback?.likeCount,
        commentCount: fallback?.commentCount,
        shareCount: fallback?.shareCount,
      );
    } catch (_) {
      return null;
    }
  }

  /// The embed player ships the media URL inside a `contextJSON` blob.
  Future<VideoMetadata?> _fromEmbedPage(
    String shortcode,
    String url,
    AppLocalizations l10n,
  ) async {
    final String html;
    try {
      final response = await ExtractorHttp.get(
        'https://www.instagram.com/p/$shortcode/embed/captioned/',
        userAgent: AppConstants.defaultUserAgent,
      );
      if (response.statusCode >= 400) return null;
      html = response.body;
    } catch (_) {
      return null;
    }

    final videoUrl = _firstGroup(html, [
      RegExp(r'"video_url"\s*:\s*"([^"]+)"'),
      RegExp(r'"video_versions"\s*:\s*\[\{[^}]*"url"\s*:\s*"([^"]+)"'),
      RegExp(r'<meta[^>]+property="og:video"[^>]+content="([^"]+)"'),
    ]);
    if (videoUrl == null) {
      final imageUrls = _extractImageUrls(html);
      if (imageUrls.isEmpty) return null;
      return _buildImages(
        l10n: l10n,
        shortcode: shortcode,
        originalUrl: url,
        imageUrls: imageUrls,
        author: _firstGroup(html, [
          RegExp(r'"username"\s*:\s*"([^"]+)"'),
          RegExp(r'"owner"\s*:\s*\{[^}]*"username"\s*:\s*"([^"]+)"'),
        ]),
        caption: _firstGroup(html, [
          RegExp(
            r'"edge_media_to_caption":\{"edges":\[\{"node":\{"text":"([^"]*)"',
          ),
          RegExp(r'"caption"\s*:\s*"([^"]{1,400})"'),
        ]),
      );
    }

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      imageUrls: _extractImageUrls(html, includeFallback: false),
      thumbnail: _firstGroup(html, [
        RegExp(r'"display_url":"([^"]+)"'),
        RegExp(r'"thumbnail_src":"([^"]+)"'),
        RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'),
      ]),
      author: _firstGroup(html, [
        RegExp(r'"username"\s*:\s*"([^"]+)"'),
        RegExp(r'"owner"\s*:\s*\{[^}]*"username"\s*:\s*"([^"]+)"'),
      ]),
      caption: _firstGroup(html, [
        RegExp(
          r'"edge_media_to_caption":\{"edges":\[\{"node":\{"text":"([^"]*)"',
        ),
        RegExp(r'"caption"\s*:\s*"([^"]{1,400})"'),
      ]),
      durationSeconds: _duration(html),
      viewCount:
          _intField(html, 'video_view_count') ?? _intField(html, 'play_count'),
      likeCount:
          _intField(html, 'edge_media_preview_like') ??
          _intField(html, 'like_count'),
    );
  }

  /// The post page still exposes an `og:video` tag for some public Reels.
  Future<VideoMetadata?> _fromPostPage(
    String shortcode,
    String url,
    AppLocalizations l10n,
  ) async {
    final String html;
    try {
      final response = await ExtractorHttp.get(
        'https://www.instagram.com/p/$shortcode/',
        userAgent: AppConstants.mobileUserAgent,
      );
      if (response.statusCode >= 400) return null;
      html = response.body;
    } catch (_) {
      return null;
    }

    final videoUrl = _firstGroup(html, [
      RegExp(r'<meta[^>]+property="og:video"[^>]+content="([^"]+)"'),
      RegExp(r'"video_url"\s*:\s*"([^"]+)"'),
    ]);
    if (videoUrl == null) {
      final imageUrls = _extractImageUrls(html);
      if (imageUrls.isEmpty) return null;
      return _buildImages(
        l10n: l10n,
        shortcode: shortcode,
        originalUrl: url,
        imageUrls: imageUrls,
        author: _firstGroup(html, [RegExp(r'"username"\s*:\s*"([^"]+)"')]),
        caption: _firstGroup(html, [
          RegExp(r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"'),
        ]),
      );
    }

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      imageUrls: _extractImageUrls(html, includeFallback: false),
      thumbnail: _firstGroup(html, [
        RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'),
      ]),
      author: _firstGroup(html, [RegExp(r'"username"\s*:\s*"([^"]+)"')]),
      caption: _firstGroup(html, [
        RegExp(r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"'),
      ]),
      durationSeconds: _duration(html),
      viewCount: null,
      likeCount: null,
    );
  }

  VideoMetadata _build({
    required AppLocalizations l10n,
    required String shortcode,
    required String originalUrl,
    required String videoUrl,
    List<String> imageUrls = const [],
    required String? thumbnail,
    required String? author,
    required String? caption,
    required int? durationSeconds,
    required int? viewCount,
    required int? likeCount,
  }) {
    final cleanCaption = caption == null || caption.trim().isEmpty
        ? null
        : decodeHtmlEntities(decodeJsonEscapes(caption)).trim();
    final username = author == null || author.isEmpty
        ? 'Instagram'
        : decodeJsonEscapes(author);

    return VideoMetadata(
      id: shortcode,
      originalUrl: originalUrl,
      title: cleanCaption != null && cleanCaption.isNotEmpty
          ? cleanCaption
          : 'Instagram Video ($shortcode)',
      description: cleanCaption,
      author: username,
      coverUrl: thumbnail == null
          ? ''
          : decodeHtmlEntities(decodeJsonEscapes(thumbnail)),
      duration: durationSeconds != null && durationSeconds > 0
          ? Duration(seconds: durationSeconds)
          : null,
      platform: VideoPlatform.instagram,
      qualities: QualityHelper.sortedByQuality([
        VideoQualityOption(
          id: 'ig_$shortcode',
          mediaId: 'ig_video_$shortcode',
          label: l10n.originalMp4,
          quality: 'Original',
          format: 'mp4',
          downloadUrl: decodeHtmlEntities(decodeJsonEscapes(videoUrl)),
        ),
        for (var index = 0; index < imageUrls.length; index++)
          VideoQualityOption(
            id: 'ig_image_${index + 1}_$shortcode',
            mediaId: 'ig_image_${index + 1}_$shortcode',
            label: l10n.imageLabel(index + 1),
            quality: 'Original',
            format: _imageFormat(imageUrls[index]),
            downloadUrl: decodeHtmlEntities(
              decodeJsonEscapes(imageUrls[index]),
            ),
            kind: MediaKind.image,
          ),
      ]),
      viewCount: viewCount,
      likeCount: likeCount,
    );
  }

  VideoMetadata _buildImages({
    required AppLocalizations l10n,
    required String shortcode,
    required String originalUrl,
    required List<String> imageUrls,
    required String? author,
    required String? caption,
  }) {
    final cleanCaption = caption == null || caption.trim().isEmpty
        ? null
        : decodeHtmlEntities(decodeJsonEscapes(caption)).trim();
    final username = author == null || author.isEmpty
        ? 'Instagram'
        : decodeJsonEscapes(author);
    final decodedUrls = imageUrls
        .map((url) => decodeHtmlEntities(decodeJsonEscapes(url)))
        .toList();

    return VideoMetadata(
      id: shortcode,
      originalUrl: originalUrl,
      title: cleanCaption != null && cleanCaption.isNotEmpty
          ? cleanCaption
          : 'Instagram Post ($shortcode)',
      description: cleanCaption,
      author: username,
      coverUrl: decodedUrls.first,
      platform: VideoPlatform.instagram,
      qualities: [
        for (var index = 0; index < decodedUrls.length; index++)
          VideoQualityOption(
            id: 'ig_image_${index + 1}_$shortcode',
            mediaId: 'ig_image_${index + 1}_$shortcode',
            label: l10n.imageLabel(index + 1),
            quality: l10n.imageLabel(index + 1),
            format: _imageFormat(decodedUrls[index]),
            downloadUrl: decodedUrls[index],
            kind: MediaKind.image,
          ),
      ],
    );
  }

  List<String> _extractImageUrls(String html, {bool includeFallback = true}) {
    final urls = <String>[];

    void addUrl(dynamic value) {
      final url = value?.toString() ?? '';
      if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
    }

    void addMedia(dynamic value) {
      if (value is! Map<String, dynamic>) return;
      if (value['is_video'] == true || value['media_type'] == 2) return;
      final node = value['node'];
      if (node is Map<String, dynamic>) {
        addMedia(node);
        return;
      }
      final displayUrl = value['display_url'];
      if (displayUrl != null) {
        addUrl(displayUrl);
        return;
      }
      final versions = value['image_versions2'];
      if (versions is Map<String, dynamic>) {
        final candidates = versions['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final first = candidates.first;
          if (first is Map<String, dynamic>) addUrl(first['url']);
        }
      }
    }

    void visit(dynamic value) {
      if (value is Map<String, dynamic>) {
        final carousel = value['carousel_media'];
        if (carousel is List) {
          for (final item in carousel) {
            addMedia(item);
          }
        }
        final sidecar = value['edge_sidecar_to_children'];
        if (sidecar is Map<String, dynamic>) {
          final edges = sidecar['edges'];
          if (edges is List) {
            for (final edge in edges) {
              addMedia(edge);
            }
          }
        }
        for (final child in value.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
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
        // Instagram changes its bootstrap payload often; the metadata fallbacks
        // below still cover simple public image posts.
      }
    }

    if (includeFallback && urls.isEmpty) {
      for (final match in RegExp(r'"display_url":"([^"]+)"').allMatches(html)) {
        addUrl(match.group(1));
      }
    }
    if (includeFallback && urls.isEmpty) {
      addUrl(
        RegExp(
          r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(html)?.group(1),
      );
    }
    return urls;
  }

  String _imageFormat(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.png')) return 'png';
    if (path.endsWith('.webp')) return 'webp';
    return 'jpg';
  }

  String? _firstGroup(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int? _intField(String html, String key) {
    final value =
        RegExp('"$key":\\{?"?count"?:?\\s*(\\d+)').firstMatch(html) ??
        RegExp('"$key":(\\d+)').firstMatch(html);
    return int.tryParse(value?.group(1) ?? '');
  }

  int? _duration(String html) {
    final value = RegExp(
      r'"video_duration":([\d.]+)',
    ).firstMatch(html)?.group(1);
    return double.tryParse(value ?? '')?.round();
  }
}
