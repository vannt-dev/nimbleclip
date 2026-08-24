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
    '.jpg': 'jpg',
    '.jpeg': 'jpg',
    '.png': 'png',
    '.gif': 'gif',
    '.webp': 'webp',
    '.avif': 'avif',
  };

  static const Set<String> _audioFormats = {'mp3', 'm4a', 'aac', 'wav', 'ogg'};
  static const Set<String> _imageFormats = {
    'jpg',
    'png',
    'gif',
    'webp',
    'avif',
  };

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

    // An extensionless media URL may point at a multi-gigabyte file. Probe its
    // headers first so extraction never buffers the payload just to inspect
    // Content-Type. Fixture tests intentionally bypass this network probe.
    if (!ExtractorHttp.isUsingOverrides) {
      try {
        final head = await ExtractorHttp.head(
          cleanUrl,
          timeout: const Duration(seconds: 8),
        );
        final media = _fromMediaHeaders(head, uri, cleanUrl, id, l10n);
        if (media != null) return media;
      } catch (_) {
        // Many sites reject HEAD. Fall through to the HTML GET path.
      }
    }

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
    final media = _fromMediaHeaders(response, uri, cleanUrl, id, l10n);
    if (media != null) return media;

    return _fromOpenGraph(response.body, uri, cleanUrl, id, l10n);
  }

  VideoMetadata? _fromMediaHeaders(
    http.Response response,
    Uri uri,
    String cleanUrl,
    String id,
    AppLocalizations l10n,
  ) {
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (!contentType.startsWith('video/') &&
        !contentType.startsWith('audio/') &&
        !contentType.startsWith('image/')) {
      return null;
    }
    final isAudio = contentType.startsWith('audio/');
    final isImage = contentType.startsWith('image/');
    final format = _formatFromContentType(contentType, isAudio, isImage);
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
          label: isImage
              ? l10n.imageLabel(1)
              : isAudio
              ? l10n.originalAudio
              : l10n.originalVideo,
          quality: 'Original',
          format: format,
          downloadUrl: cleanUrl,
          sizeBytes: int.tryParse(response.headers['content-length'] ?? ''),
          kind: isImage
              ? MediaKind.image
              : isAudio
              ? MediaKind.audio
              : MediaKind.video,
        ),
      ],
    );
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
    final isImage = _imageFormats.contains(format);
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
          label: isImage
              ? l10n.imageLabel(1)
              : isAudio
              ? l10n.originalAudio
              : l10n.originalVideo,
          quality: 'Original',
          format: format,
          downloadUrl: url,
          kind: isImage
              ? MediaKind.image
              : isAudio
              ? MediaKind.audio
              : MediaKind.video,
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
    final image = _meta(html, ['og:image']);
    if (videoUrl == null && image == null) {
      throw ExtractionException(l10n.genericNoVideo);
    }

    // Open Graph URLs are often protocol-relative or site-relative.
    final resolved = videoUrl == null ? null : uri.resolve(videoUrl).toString();
    final resolvedImage = image == null ? null : uri.resolve(image).toString();
    final height = _meta(html, ['og:video:height']);

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: _meta(html, ['og:title']) ?? _title(html) ?? 'Web Video',
      description: _meta(html, ['og:description']),
      author: _meta(html, ['og:site_name']) ?? uri.host,
      coverUrl: resolvedImage ?? '',
      duration: _durationFrom(
        _meta(html, ['og:video:duration', 'video:duration']),
      ),
      platform: VideoPlatform.generic,
      qualities: QualityHelper.sortedByQuality([
        if (resolved != null)
          VideoQualityOption(
            id: 'gen_og_$id',
            label: l10n.embeddedVideo,
            quality: height != null ? '${height}p' : 'Original',
            format: 'mp4',
            downloadUrl: resolved,
          ),
        // On an image-only page og:image is the post media. On a video page it
        // is merely the poster and must not be downloaded as a second asset.
        if (resolved == null && resolvedImage != null)
          VideoQualityOption(
            id: 'gen_image_$id',
            label: l10n.imageLabel(1),
            quality: 'Original',
            format: _imageFormat(resolvedImage),
            downloadUrl: resolvedImage,
            kind: MediaKind.image,
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

  String _formatFromContentType(
    String contentType,
    bool isAudio,
    bool isImage,
  ) {
    final subtype = contentType.split(';').first.split('/').last;
    if (isImage) return subtype == 'jpeg' ? 'jpg' : subtype;
    if (isAudio) return subtype == 'mpeg' ? 'mp3' : subtype;
    return subtype == 'quicktime' ? 'mov' : subtype;
  }

  String _imageFormat(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    for (final entry in _mediaExtensions.entries) {
      if (_imageFormats.contains(entry.value) && path.endsWith(entry.key)) {
        return entry.value;
      }
    }
    return 'jpg';
  }
}
