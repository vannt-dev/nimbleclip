import 'package:http/http.dart' as http;

import '../../core/utils/http_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';

/// Fallback for direct media links and pages that advertise a video through
/// Open Graph tags. Registered last, so it only sees URLs no platform claimed.
class GenericExtractor extends BaseVideoExtractor {
  const GenericExtractor();

  static const Map<String, String> _mediaExtensions = {
    '.mp4': 'mp4',
    '.m4v': 'mp4',
    '.mkv': 'mkv',
    '.webm': 'webm',
    '.mov': 'mov',
    '.avi': 'avi',
    '.mp3': 'mp3',
    '.m4a': 'm4a',
    '.aac': 'aac',
    '.wav': 'wav',
    '.ogg': 'ogg',
  };

  static const Set<String> _audioFormats = {'mp3', 'm4a', 'aac', 'wav', 'ogg'};

  @override
  VideoPlatform get platform => VideoPlatform.generic;

  @override
  bool canHandle(String url) => true;

  @override
  Future<VideoMetadata> extract(String url, AppLocalizations l10n) async {
    final cleanUrl = url.trim();
    final uri = Uri.parse(cleanUrl);
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final direct = _directMediaFormat(uri);
    if (direct != null) return _directMedia(uri, cleanUrl, id, direct, l10n);

    final http.Response response;
    try {
      response = await ExtractorHttp.get(
        cleanUrl,
        timeout: const Duration(seconds: 12),
      );
    } catch (e) {
      throw ExtractionException(l10n.linkAccessFailed(e.toString()));
    }

    // The URL had no media extension but the server says it is media anyway.
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.startsWith('video/') || contentType.startsWith('audio/')) {
      final isAudio = contentType.startsWith('audio/');
      return VideoMetadata(
        id: id,
        originalUrl: cleanUrl,
        title: _fileNameOf(uri) ?? 'Media Stream ($id)',
        description: l10n.directMediaLink,
        author: uri.host,
        coverUrl: '',
        platform: VideoPlatform.generic,
        qualities: [
          VideoQualityOption(
            id: 'gen_$id',
            label: isAudio ? l10n.originalAudio : l10n.originalVideo,
            quality: 'Original',
            format: isAudio ? 'mp3' : 'mp4',
            downloadUrl: cleanUrl,
            sizeBytes: int.tryParse(response.headers['content-length'] ?? ''),
            isAudioOnly: isAudio,
          ),
        ],
      );
    }

    return _fromOpenGraph(response.body, uri, cleanUrl, id, l10n);
  }

  String? _directMediaFormat(Uri uri) {
    final path = uri.path.toLowerCase();
    for (final entry in _mediaExtensions.entries) {
      if (path.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  VideoMetadata _directMedia(
    Uri uri,
    String url,
    String id,
    String format,
    AppLocalizations l10n,
  ) {
    final isAudio = _audioFormats.contains(format);
    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: _fileNameOf(uri) ?? 'Direct_Media_$id',
      description: l10n.directMediaLink,
      author: uri.host,
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption(
          id: 'gen_$id',
          label: isAudio ? l10n.originalAudio : l10n.originalVideo,
          quality: 'Original',
          format: format,
          downloadUrl: url,
          isAudioOnly: isAudio,
        ),
      ],
    );
  }

  VideoMetadata _fromOpenGraph(
    String html,
    Uri uri,
    String url,
    String id,
    AppLocalizations l10n,
  ) {
    final videoUrl =
        _meta(html, ['og:video:secure_url', 'og:video:url', 'og:video']) ??
        _meta(html, ['twitter:player:stream']);
    if (videoUrl == null) {
      throw ExtractionException(l10n.genericNoVideo);
    }

    // Open Graph URLs are often protocol-relative or site-relative.
    final resolved = uri.resolve(videoUrl).toString();
    final image = _meta(html, ['og:image']);
    final height = _meta(html, ['og:video:height']);

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: _meta(html, ['og:title']) ?? _title(html) ?? 'Web Video',
      description: _meta(html, ['og:description']),
      author: _meta(html, ['og:site_name']) ?? uri.host,
      coverUrl: image == null ? '' : uri.resolve(image).toString(),
      duration: _durationFrom(
        _meta(html, ['og:video:duration', 'video:duration']),
      ),
      platform: VideoPlatform.generic,
      qualities: QualityHelper.sortedByQuality([
        VideoQualityOption(
          id: 'gen_og_$id',
          label: l10n.embeddedVideo,
          quality: height != null ? '${height}p' : 'Original',
          format: 'mp4',
          downloadUrl: resolved,
        ),
      ]),
    );
  }

  /// Reads a `<meta>` tag's content, tolerating either attribute order
  /// (`property` before `content` or the reverse) and `name=` instead of
  /// `property=`.
  String? _meta(String html, List<String> keys) {
    for (final key in keys) {
      final escaped = RegExp.escape(key);
      final match =
          RegExp(
            '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]*content=["\']([^"\']*)["\']',
            caseSensitive: false,
          ).firstMatch(html) ??
          RegExp(
            '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$escaped["\']',
            caseSensitive: false,
          ).firstMatch(html);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return decodeHtmlEntities(value);
    }
    return null;
  }

  String? _title(String html) {
    final raw = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html)?.group(1)?.trim();
    return raw == null || raw.isEmpty ? null : decodeHtmlEntities(raw);
  }

  String? _fileNameOf(Uri uri) {
    if (uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last;
    return last.isEmpty ? null : Uri.decodeComponent(last);
  }

  Duration? _durationFrom(String? raw) {
    final seconds = int.tryParse(raw ?? '');
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }
}
