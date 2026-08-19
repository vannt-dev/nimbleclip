import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../core/utils/url_helper.dart';
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
    RegExp(r'"browser_native_hd_url":"([^"]+)"'),
    RegExp(r'"hd_src_no_ratelimit":"([^"]+)"'),
    RegExp(r'"playable_url_quality_hd":"([^"]+)"'),
    RegExp(r'"hd_src":"([^"]+)"'),
  ];

  static final List<RegExp> _sdPatterns = [
    RegExp(r'"browser_native_sd_url":"([^"]+)"'),
    RegExp(r'"sd_src_no_ratelimit":"([^"]+)"'),
    RegExp(r'"playable_url":"([^"]+)"'),
    RegExp(r'"sd_src":"([^"]+)"'),
  ];

  String? _firstMatch(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) {
        final decoded = decodeJsonEscapes(value);
        if (decoded.startsWith('http')) return decoded;
      }
    }
    return null;
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    var cleanUrl = url.trim();
    if (UrlHelper.isShortLink(cleanUrl)) {
      cleanUrl = await ExtractorHttp.resolveRedirects(cleanUrl);
    }

    // Strategy 1: the watch page itself.
    var result = await _fromPage(cleanUrl, cleanUrl);
    if (result != null) return result;

    // Strategy 2: the embed player. It serves a much smaller page that still
    // carries the playable URLs and is less likely to be gated behind a login
    // interstitial than the full watch page.
    final embedUrl =
        'https://www.facebook.com/plugins/video.php?href=${Uri.encodeComponent(cleanUrl)}';
    result = await _fromPage(embedUrl, cleanUrl);
    if (result != null) return result;

    // Strategy 3: the mobile site, which renders a plainer document.
    final mobileUrl = cleanUrl.replaceFirst(
      RegExp(r'https?://(www\.|web\.|m\.)?facebook\.com'),
      'https://m.facebook.com',
    );
    result = await _fromPage(
      mobileUrl,
      cleanUrl,
      userAgent: AppConstants.mobileUserAgent,
    );
    if (result != null) return result;

    throw const ExtractionException(
      'Không lấy được video từ liên kết Facebook. Hãy chắc chắn video ở chế độ '
      'công khai (Public) — video riêng tư hoặc trong nhóm kín cần đăng nhập.',
    );
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
    if (hdUrl == null && sdUrl == null) return null;

    final id = _videoId(html) ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final qualities = <VideoQualityOption>[
      if (hdUrl != null)
        VideoQualityOption(
          id: 'fb_hd_$id',
          label: 'HD 720p (Chất lượng cao)',
          quality: 'HD 720p',
          format: 'mp4',
          downloadUrl: hdUrl,
        ),
      if (sdUrl != null && sdUrl != hdUrl)
        VideoQualityOption(
          id: 'fb_sd_$id',
          label: 'SD 480p (Tiêu chuẩn)',
          quality: 'SD 480p',
          format: 'mp4',
          downloadUrl: sdUrl,
        ),
    ];

    return VideoMetadata(
      id: id,
      originalUrl: originalUrl,
      title: _title(html),
      description: _stringField(html, 'message') ?? _stringField(html, 'title'),
      author: _owner(html) ?? 'Facebook',
      coverUrl: _thumbnail(html) ?? '',
      duration: _duration(html),
      platform: VideoPlatform.facebook,
      qualities: QualityHelper.sortedByQuality(qualities),
    );
  }

  String? _videoId(String html) =>
      RegExp(r'"video_id":"(\d+)"').firstMatch(html)?.group(1) ??
      RegExp(r'"videoId":"(\d+)"').firstMatch(html)?.group(1);

  String _title(String html) {
    final ogTitle =
        RegExp(r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"')
            .firstMatch(html)
            ?.group(1);
    final rawTitle = ogTitle ??
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
            .firstMatch(html)
            ?.group(1);
    if (rawTitle == null || rawTitle.trim().isEmpty) return 'Facebook Video';

    final title = decodeHtmlEntities(decodeJsonEscapes(rawTitle))
        .replaceAll(RegExp(r'\s*\|\s*Facebook\s*$'), '')
        .trim();
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
    final raw = RegExp(r'"preferred_thumbnail":\{"image":\{"uri":"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        RegExp(r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"')
            .firstMatch(html)
            ?.group(1);
    return raw == null ? null : decodeHtmlEntities(decodeJsonEscapes(raw));
  }

  Duration? _duration(String html) {
    final ms = RegExp(r'"playable_duration_in_ms":(\d+)')
        .firstMatch(html)
        ?.group(1);
    if (ms != null) {
      final value = int.tryParse(ms);
      if (value != null && value > 0) return Duration(milliseconds: value);
    }
    final seconds =
        RegExp(r'"video_duration":(\d+)').firstMatch(html)?.group(1);
    final value = int.tryParse(seconds ?? '');
    return value != null && value > 0 ? Duration(seconds: value) : null;
  }
}
