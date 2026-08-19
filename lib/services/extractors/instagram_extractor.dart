import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
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

  @override
  VideoPlatform get platform => VideoPlatform.instagram;

  static final RegExp _shortcodePattern =
      RegExp(r'/(?:reels?|p|tv)/([A-Za-z0-9_-]+)');

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
    if (viaEmbed != null) return viaEmbed;

    final viaPage = await _fromPostPage(shortcode, cleanUrl, l10n);
    if (viaPage != null) return viaPage;

    throw ExtractionException(l10n.instagramLoginRequired);
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
      RegExp(r'"video_url":"([^"]+)"'),
      RegExp(r'"video_versions":\[\{[^}]*"url":"([^"]+)"'),
      RegExp(r'<meta[^>]+property="og:video"[^>]+content="([^"]+)"'),
    ]);
    if (videoUrl == null) return null;

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      thumbnail: _firstGroup(html, [
        RegExp(r'"display_url":"([^"]+)"'),
        RegExp(r'"thumbnail_src":"([^"]+)"'),
        RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'),
      ]),
      author: _firstGroup(html, [
        RegExp(r'"username":"([^"]+)"'),
        RegExp(r'"owner":\{[^}]*"username":"([^"]+)"'),
      ]),
      caption: _firstGroup(html, [
        RegExp(r'"edge_media_to_caption":\{"edges":\[\{"node":\{"text":"([^"]*)"'),
        RegExp(r'"caption":"([^"]{1,400})"'),
      ]),
      durationSeconds: _duration(html),
      viewCount: _intField(html, 'video_view_count') ??
          _intField(html, 'play_count'),
      likeCount: _intField(html, 'edge_media_preview_like') ??
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
      RegExp(r'"video_url":"([^"]+)"'),
    ]);
    if (videoUrl == null) return null;

    return _build(
      l10n: l10n,
      shortcode: shortcode,
      originalUrl: url,
      videoUrl: videoUrl,
      thumbnail: _firstGroup(html, [
        RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'),
      ]),
      author: _firstGroup(html, [RegExp(r'"username":"([^"]+)"')]),
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
          label: l10n.originalMp4,
          quality: 'Original',
          format: 'mp4',
          downloadUrl: decodeHtmlEntities(decodeJsonEscapes(videoUrl)),
        ),
      ]),
      viewCount: viewCount,
      likeCount: likeCount,
    );
  }

  String? _firstGroup(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int? _intField(String html, String key) {
    final value = RegExp('"$key":\\{?"?count"?:?\\s*(\\d+)').firstMatch(html) ??
        RegExp('"$key":(\\d+)').firstMatch(html);
    return int.tryParse(value?.group(1) ?? '');
  }

  int? _duration(String html) {
    final value = RegExp(r'"video_duration":([\d.]+)').firstMatch(html)?.group(1);
    return double.tryParse(value ?? '')?.round();
  }
}
