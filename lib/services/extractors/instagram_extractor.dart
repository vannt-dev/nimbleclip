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
import 'extraction_failure.dart';
import 'instagram_fallback_client.dart';
import 'instagram_page_parser.dart';
import 'parse_offloading.dart';

/// Isolate entry points for [InstagramExtractor.extractImageUrls]. Both must be
/// top-level so they can be sent across an isolate boundary.
List<String> _imageUrlsWithFallback(String html) =>
    InstagramExtractor.extractImageUrls(html);

List<String> _imageUrlsWithoutFallback(String html) =>
    InstagramExtractor.extractImageUrls(html, includeFallback: false);

/// Instagram extractor for public Reels and feed videos.
///
/// Instagram gates most content behind a login wall and rotates its internal
/// endpoints frequently, so this works on a best-effort basis: the embed page is
/// tried first because it is the only surface that still renders without a
/// session for public posts. When every strategy fails the user is told plainly
/// that the post needs a login rather than being handed a broken download.
class InstagramExtractor extends BaseVideoExtractor {
  final ExternalServiceAccess externalServiceAccess;
  final InstagramFallbackClient fallbackClient;
  static const _pageParser = InstagramPageParser();

  const InstagramExtractor({
    ExternalServiceAccess? externalServiceAccess,
    InstagramFallbackClient? fallbackClient,
  }) : externalServiceAccess =
           externalServiceAccess ?? const FixedExternalServiceAccess(true),
       fallbackClient = fallbackClient ?? const SnapInstaFallbackClient();

  @override
  VideoPlatform get platform => VideoPlatform.instagram;

  static final RegExp _shortcodePattern = RegExp(
    r'/(?:reels?|p|tv)/([A-Za-z0-9_-]+)',
  );

  /// Same scan as [extractImageUrls], moved off the UI isolate for documents
  /// large enough to be worth the hand-off.
  static Future<List<String>> _extractImageUrlsAsync(
    String html, {
    bool includeFallback = true,
  }) => parseOffMainIsolate(
    includeFallback ? _imageUrlsWithFallback : _imageUrlsWithoutFallback,
    html,
    debugLabel: 'instagram.imageUrls',
  );

  // Hoisted so the fallback-result loop below does not recompile seven
  // expressions for every `<li>` in a carousel.
  static final RegExp _listItem = RegExp(
    r'<li[^>]*>([\s\S]*?)</li>',
    caseSensitive: false,
  );
  static final List<RegExp> _previewPatterns = [
    RegExp(r'<img[^>]+data-src="([^"]+)"', caseSensitive: false),
    RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false),
  ];
  static final RegExp _looksVideo = RegExp(
    r'icon-dlvideo|<video|(?:type|media)[-_ ]?video|download[-_ ]?video',
    caseSensitive: false,
  );
  static final List<RegExp> _videoDownloadPatterns = [
    RegExp(
      r'<a[^>]*title="[^"]*video"[^>]*href="(https://dl\.snapcdn\.app/get\?[^"]+)"[^>]*>',
      caseSensitive: false,
    ),
    RegExp(
      r'<a[^>]+href="(https://dl\.snapcdn\.app/get\?[^"]+)"[^>]*>[\s\S]*?(?:Tải|Download)[^<]*video',
      caseSensitive: false,
    ),
  ];
  static final List<RegExp> _downloadPatterns = [
    RegExp(r'<option[^>]+value="([^"]+)"', caseSensitive: false),
    RegExp(
      r'<a[^>]+href="(https://dl\.snapcdn\.app/get\?[^"]+)"',
      caseSensitive: false,
    ),
  ];

  static final RegExp _ogVideo = RegExp(
    r'<meta[^>]+property="og:video"[^>]+content="([^"]+)"',
  );
  static final RegExp _ogImage = RegExp(
    r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
  );
  static final RegExp _ogTitle = RegExp(
    r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"',
  );
  static final RegExp _videoUrlField = RegExp(r'"video_url"\s*:\s*"([^"]+)"');
  static final RegExp _videoVersionsField = RegExp(
    r'"video_versions"\s*:\s*\[\{[^}]*"url"\s*:\s*"([^"]+)"',
  );
  static final RegExp _usernameField = RegExp(r'"username"\s*:\s*"([^"]+)"');
  static final RegExp _ownerUsernameField = RegExp(
    r'"owner"\s*:\s*\{[^}]*"username"\s*:\s*"([^"]+)"',
  );
  static final RegExp _captionField = RegExp(
    r'"caption"\s*:\s*"([^"]{1,400})"',
  );
  static final RegExp _captionEdgeField = RegExp(
    r'"edge_media_to_caption":\{"edges":\[\{"node":\{"text":"([^"]*)"',
  );

  static final List<RegExp> _authorPatterns = [
    _usernameField,
    _ownerUsernameField,
  ];
  static final List<RegExp> _captionPatterns = [
    _captionEdgeField,
    _captionField,
  ];
  static final List<RegExp> _embedVideoPatterns = [
    _videoUrlField,
    _videoVersionsField,
    _ogVideo,
  ];
  static final List<RegExp> _postPageVideoPatterns = [_ogVideo, _videoUrlField];
  static final List<RegExp> _thumbnailPatterns = [
    _displayUrlField,
    _thumbnailSrcField,
    _ogImage,
  ];
  static final RegExp _displayUrlField = RegExp(r'"display_url":"([^"]+)"');
  static final RegExp _thumbnailSrcField = RegExp(r'"thumbnail_src":"([^"]+)"');
  static final RegExp _jsonScripts = RegExp(
    r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  );
  // The image fallback below matches the tag case-insensitively, unlike the
  // `og:image` lookup used for thumbnails. Kept as a separate pattern so the
  // two call sites keep the behaviour they had.
  static final RegExp _ogImageInsensitive = RegExp(
    r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
    caseSensitive: false,
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
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.instagramInvalidPost),
      );
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

    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.instagramLoginRequired),
    );
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
    if (!externalServiceAccess.allowExternalServices) return fallback;
    try {
      final resultHtml = await fallbackClient.search(url);
      if (resultHtml == null) return null;

      final downloadUrls = <String>[];
      final previewUrls = <String>[];
      final mediaKinds = <MediaKind>[];
      final sourcePath = Uri.tryParse(url)?.path.toLowerCase() ?? '';
      final sourceIsVideo =
          sourcePath.contains('/reel/') ||
          sourcePath.contains('/reels/') ||
          sourcePath.contains('/tv/');
      for (final match in _listItem.allMatches(resultHtml)) {
        final item = match.group(1) ?? '';
        final preview = _firstGroup(item, _previewPatterns);
        final itemLooksVideo = _looksVideo.hasMatch(item);
        final videoDownload = itemLooksVideo
            ? _firstGroup(item, _videoDownloadPatterns)
            : null;
        final download = videoDownload ?? _firstGroup(item, _downloadPatterns);
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

    final videoUrl = _firstGroup(html, _embedVideoPatterns);
    if (videoUrl == null) {
      final imageUrls = await _extractImageUrlsAsync(html);
      if (imageUrls.isEmpty) return null;
      return _buildImages(
        l10n: l10n,
        shortcode: shortcode,
        originalUrl: url,
        imageUrls: imageUrls,
        author: _firstGroup(html, _authorPatterns),
        caption: _firstGroup(html, _captionPatterns),
      );
    }

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      imageUrls: await _extractImageUrlsAsync(html, includeFallback: false),
      thumbnail: _firstGroup(html, _thumbnailPatterns),
      author: _firstGroup(html, _authorPatterns),
      caption: _firstGroup(html, _captionPatterns),
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

    final videoUrl = _firstGroup(html, _postPageVideoPatterns);
    if (videoUrl == null) {
      final imageUrls = await _extractImageUrlsAsync(html);
      if (imageUrls.isEmpty) return null;
      return _buildImages(
        l10n: l10n,
        shortcode: shortcode,
        originalUrl: url,
        imageUrls: imageUrls,
        author: _firstGroup(html, [_usernameField]),
        caption: _firstGroup(html, [_ogTitle]),
      );
    }

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      imageUrls: await _extractImageUrlsAsync(html, includeFallback: false),
      thumbnail: _firstGroup(html, [_ogImage]),
      author: _firstGroup(html, [_usernameField]),
      caption: _firstGroup(html, [_ogTitle]),
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
        : MediaUrlHelper.decode(caption).trim();
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
      coverUrl: thumbnail == null ? '' : MediaUrlHelper.decode(thumbnail),
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
          downloadUrl: MediaUrlHelper.decode(videoUrl),
        ),
        for (var index = 0; index < imageUrls.length; index++)
          VideoQualityOption.image(
            id: 'ig_image_${index + 1}_$shortcode',
            mediaId: 'ig_image_${index + 1}_$shortcode',
            label: l10n.imageLabel(index + 1),
            quality: 'Original',
            format: MediaFormatHelper.inferImageFormat(imageUrls[index]),
            downloadUrl: MediaUrlHelper.decode(imageUrls[index]),
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
        : MediaUrlHelper.decode(caption).trim();
    final username = author == null || author.isEmpty
        ? 'Instagram'
        : decodeJsonEscapes(author);
    final decodedUrls = imageUrls.map(MediaUrlHelper.decode).toList();

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
          VideoQualityOption.image(
            id: 'ig_image_${index + 1}_$shortcode',
            mediaId: 'ig_image_${index + 1}_$shortcode',
            label: l10n.imageLabel(index + 1),
            quality: l10n.imageLabel(index + 1),
            format: MediaFormatHelper.inferImageFormat(decodedUrls[index]),
            downloadUrl: decodedUrls[index],
          ),
      ],
    );
  }

  /// Scans a post document for image URLs.
  ///
  /// Static and free of instance state so it can run on a background isolate:
  /// decoding and walking every inline JSON block is the heaviest step of an
  /// Instagram extraction.
  static List<String> extractImageUrls(
    String html, {
    bool includeFallback = true,
  }) {
    final urls = <String>[];
    final seen = <String>{};

    void addUrl(dynamic value) {
      final url = value?.toString() ?? '';
      if (url.isNotEmpty && seen.add(url)) urls.add(url);
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

    final scripts = _jsonScripts.allMatches(html);
    for (final script in scripts) {
      try {
        visit(jsonDecode(decodeHtmlEntities(script.group(1) ?? '')));
      } catch (_) {
        // Instagram changes its bootstrap payload often; the metadata fallbacks
        // below still cover simple public image posts.
      }
    }

    if (includeFallback && urls.isEmpty) {
      for (final match in _displayUrlField.allMatches(html)) {
        addUrl(match.group(1));
      }
    }
    if (includeFallback && urls.isEmpty) {
      addUrl(_ogImageInsensitive.firstMatch(html)?.group(1));
    }
    return urls;
  }

  String? _firstGroup(String html, List<RegExp> patterns) {
    return _pageParser.firstGroup(html, patterns);
  }

  int? _intField(String html, String key) {
    return _pageParser.intField(html, key);
  }

  int? _duration(String html) {
    return _pageParser.durationSeconds(html);
  }
}
