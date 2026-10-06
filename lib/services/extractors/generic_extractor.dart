import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../models/hls_source.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import '../hls/hls_playlist.dart';
import '../slideshow/slideshow_renderer.dart';
import 'extraction_failure.dart';

/// Fallback for direct media links and for pages that declare their media in
/// a standard way: Open Graph tags, `<video>` / `<audio>` elements or JSON-LD.
/// Registered last, so it only sees URLs no platform claimed.
///
/// A video served as an HLS stream is offered where the device can join its
/// segments into a file; elsewhere it is reported as a stream.
class GenericExtractor extends BaseVideoExtractor {
  const GenericExtractor({this.canJoinStreams});

  /// Overrides the platform check behind [joinStreams]; null asks the device.
  final bool? canJoinStreams;

  /// Whether a stream can be turned into a file here. Decided in the
  /// extractor rather than filtered in the UI, as for YouTube's merged
  /// qualities: an option the device cannot produce must not be offered.
  bool get joinStreams =>
      canJoinStreams ?? createSlideshowRenderer().isSupported;

  /// Qualities offered of one stream; a master playlist can list a dozen.
  static const int _maxStreamQualities = 6;

  static const Set<String> _playlistContentTypes = {
    'application/vnd.apple.mpegurl',
    'application/x-mpegurl',
    'audio/mpegurl',
    'audio/x-mpegurl',
  };

  /// A playlist address anywhere in a page: players built in JavaScript name
  /// their stream in a script rather than in a tag. Slashes may be escaped.
  static final RegExp _playlistInPage = RegExp(
    r'''https?:(?:\\?/){2}[^\s"'<>]+?\.m3u8(?:\?[^\s"'<>\\]*)?''',
  );

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
  Future<VideoMetadata> extract(String url) async {
    final cleanUrl = url.trim();
    final uri = Uri.parse(cleanUrl);
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    final direct = _directMediaFormat(uri);
    if (direct != null) return _directMedia(uri, cleanUrl, id, direct);
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      return _fromStream(cleanUrl, uri, cleanUrl, id);
    }

    // An extensionless media URL may point at a multi-gigabyte file. Probe its
    // headers first so extraction never buffers the payload just to inspect
    // Content-Type. Fixture tests intentionally bypass this network probe.
    if (!ExtractorHttp.isUsingOverrides) {
      try {
        final head = await ExtractorHttp.head(
          cleanUrl,
          timeout: const Duration(seconds: 8),
        );
        final media = _fromMediaHeaders(head, uri, cleanUrl, id);
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
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: e.toString(),
        ),
      );
    }

    // The URL had no media extension but the server says it is media anyway.
    final media = _fromMediaHeaders(response, uri, cleanUrl, id);
    if (media != null) return media;
    if (_isPlaylistResponse(response)) {
      return _fromStream(cleanUrl, uri, cleanUrl, id, playlist: response.body);
    }

    // What the page declares as files comes first. A page whose player is
    // built in JavaScript declares at most a poster picture, so when there is
    // no video or audio among it, a stream the page names is what was meant.
    VideoMetadata? declared;
    ExtractionException? refusal;
    try {
      declared = _fromPage(response.body, uri, cleanUrl, id);
      if (declared.qualities.any((option) => !option.isImage)) return declared;
    } on ExtractionException catch (error) {
      refusal = error;
    }

    final stream = _streamIn(response.body, uri);
    if (stream != null && joinStreams) {
      try {
        return await _fromStream(
          stream,
          uri,
          cleanUrl,
          id,
          title: _meta(response.body, ['og:title']) ?? _title(response.body),
          author: _meta(response.body, ['og:site_name']),
          coverUrl: _PageMedia(uri).resolve(_meta(response.body, ['og:image'])),
        );
      } on ExtractionException catch (error) {
        // A stream that is live or encrypted is the answer; one that merely
        // could not be read leaves the page's own verdict standing.
        final kind = error.failure.kind;
        if (kind == ExtractionFailureKind.genericStreamLive ||
            kind == ExtractionFailureKind.genericStreamProtected) {
          rethrow;
        }
      }
    }

    if (declared != null) return declared;
    throw stream == null
        ? refusal!
        : ExtractionException(
            const ExtractionFailure(ExtractionFailureKind.genericStreamOnly),
          );
  }

  static bool _isPlaylistResponse(http.Response response) {
    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    return _playlistContentTypes.contains(contentType) ||
        response.body.trimLeft().startsWith('#EXTM3U');
  }

  /// The first HLS playlist [html] names, in a tag or in a script.
  static String? _streamIn(String html, Uri page) {
    final match = _playlistInPage.firstMatch(html);
    if (match == null) return null;
    final address = match
        .group(0)!
        .replaceAll(r'\/', '/')
        .replaceAll(r'&', '&')
        .replaceAll('&amp;', '&');
    return _PageMedia(page).resolve(address);
  }

  /// Offers the qualities of the stream at [playlistUrl].
  Future<VideoMetadata> _fromStream(
    String playlistUrl,
    Uri page,
    String url,
    String id, {
    String? playlist,
    String? title,
    String? author,
    String? coverUrl,
  }) async {
    if (!joinStreams) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.genericStreamOnly),
      );
    }
    final base = Uri.parse(playlistUrl);
    final body = playlist ?? await _playlist(playlistUrl);

    final List<VideoQualityOption> qualities;
    final HlsMedia media;
    if (isHlsMaster(body)) {
      final master = parseHlsMaster(body, base);
      // One per size: several bitrates of the same picture are not a choice
      // worth a row each. The list is best first, so the first one stays -
      // unless it is in a codec the device may not be able to write to a
      // file, and the same size is also there in one every device can.
      final bySize = <int?, HlsVariant>{};
      for (final variant in master.variants) {
        final kept = bySize[variant.shortSide];
        if (kept == null || (!kept.joinsAnywhere && variant.joinsAnywhere)) {
          bySize[variant.shortSide] = variant;
        }
      }
      final variants = bySize.values.take(_maxStreamQualities).toList();
      if (variants.isEmpty) {
        throw ExtractionException(
          const ExtractionFailure(ExtractionFailureKind.genericNoVideo),
        );
      }
      // Every quality of one stream is live or encrypted alike, so the best
      // one answers for all of them.
      media = parseHlsMedia(
        await _playlist(variants.first.url),
        Uri.parse(variants.first.url),
      );
      qualities = [
        for (final variant in variants)
          VideoQualityOption.stream(
            id: 'gen_hls_${variant.shortSide ?? variant.bandwidth}',
            label: variant.shortSide == null
                ? const OriginalVideo()
                : VideoWithAudio('${variant.shortSide}p'),
            quality: variant.shortSide == null
                ? 'Original'
                : '${variant.shortSide}p',
            source: HlsSource(
              videoPlaylistUrl: variant.url,
              audioPlaylistUrl: master.audio[variant.audioGroup],
              playlistUrl: playlistUrl,
            ),
          ),
      ];
    } else {
      media = parseHlsMedia(body, base);
      qualities = [
        VideoQualityOption.stream(
          id: 'gen_hls',
          label: const OriginalVideo(),
          quality: 'Original',
          source: HlsSource(videoPlaylistUrl: playlistUrl),
        ),
      ];
    }

    if (media.isEncrypted) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.genericStreamProtected),
      );
    }
    if (!media.isComplete) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.genericStreamLive),
      );
    }
    if (media.segments.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.genericNoVideo),
      );
    }

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: title ?? _fileNameOf(base) ?? 'Web Video',
      description: null,
      author: author ?? page.host,
      coverUrl: coverUrl ?? '',
      duration: media.duration > Duration.zero ? media.duration : null,
      platform: VideoPlatform.generic,
      qualities: qualities,
    );
  }

  Future<String> _playlist(String url) async {
    final http.Response response;
    try {
      response = await ExtractorHttp.get(
        url,
        timeout: const Duration(seconds: 12),
      );
    } catch (error) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: error.toString(),
        ),
      );
    }
    if (response.statusCode >= 400) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: 'HTTP ${response.statusCode}',
        ),
      );
    }
    return response.body;
  }

  VideoMetadata? _fromMediaHeaders(
    http.Response response,
    Uri uri,
    String cleanUrl,
    String id,
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
      // Nothing renders VideoMetadata.description; this was filler text.
      description: null,
      author: uri.host,
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption(
          id: 'gen_$id',
          label: isImage
              ? const ImageIndex(1)
              : isAudio
              ? const OriginalAudio()
              : const OriginalVideo(),
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

  VideoMetadata _directMedia(Uri uri, String url, String id, String format) {
    final isAudio = _audioFormats.contains(format);
    final isImage = _imageFormats.contains(format);
    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: _fileNameOf(uri) ?? 'Direct_Media_$id',
      // Nothing renders VideoMetadata.description; this was filler text.
      description: null,
      author: uri.host,
      coverUrl: '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption(
          id: 'gen_$id',
          label: isImage
              ? const ImageIndex(1)
              : isAudio
              ? const OriginalAudio()
              : const OriginalVideo(),
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

  /// Reads a page for the media it declares in standard ways: Open Graph and
  /// Twitter card tags, `<video>` / `<audio>` elements, and JSON-LD.
  ///
  /// Nothing here is specific to a site, which is the point: it is what makes
  /// "any other link" work on blogs, news sites and forums without a parser
  /// per site.
  VideoMetadata _fromPage(String html, Uri uri, String url, String id) {
    final media = _PageMedia(uri);

    for (final key in const [
      'og:video:secure_url',
      'og:video:url',
      'og:video',
      'twitter:player:stream',
    ]) {
      _metaAll(html, key).forEach(media.addVideo);
    }
    for (final key in const ['og:audio:secure_url', 'og:audio']) {
      _metaAll(html, key).forEach(media.addAudio);
    }

    String? poster;
    for (final tag in _mediaTag.allMatches(html)) {
      final isAudio = tag.group(1)!.toLowerCase() == 'audio';
      final attributes = tag.group(2) ?? '';
      // The <source> children of one element are the same clip in several
      // encodings, so the element contributes one download, not one each.
      final encodings = [
        _attribute(attributes, 'src'),
        for (final source in _sourceTag.allMatches(tag.group(3) ?? ''))
          _attribute(source.group(1) ?? '', 'src'),
      ];
      if (isAudio) {
        media.addAudio(media.preferred(encodings, const ['.mp3', '.m4a']));
      } else {
        media.addVideo(media.preferred(encodings, const ['.mp4', '.m4v']));
        poster ??= _attribute(attributes, 'poster');
      }
    }

    for (final script in _ldJson.allMatches(html)) {
      try {
        _readLinkedData(jsonDecode(script.group(1) ?? ''), media);
      } catch (_) {
        // Hand-written JSON-LD is often invalid; the other sources still apply.
      }
    }

    // On an image-only page og:image is the post media. On a page with a
    // video or audio it is merely the poster and must not be offered as a
    // second download.
    final ogImages = _metaAll(html, 'og:image').toList();
    final hasPlayable = media.videos.isNotEmpty || media.audio.isNotEmpty;
    if (!hasPlayable) ogImages.forEach(media.addImage);

    if (media.isEmpty) {
      throw ExtractionException(
        ExtractionFailure(
          media.sawStream
              ? ExtractionFailureKind.genericStreamOnly
              : ExtractionFailureKind.genericNoVideo,
        ),
      );
    }

    final cover = [
      ...ogImages,
      ?poster,
    ].map(media.resolve).whereType<String>().firstOrNull;
    final videos = media.videos.toList();
    final images = media.images.take(_maxPageImages).toList();
    final height = _meta(html, ['og:video:height']);

    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: _meta(html, ['og:title']) ?? _title(html) ?? 'Web Video',
      description: _meta(html, ['og:description']),
      author: _meta(html, ['og:site_name']) ?? uri.host,
      coverUrl: cover ?? '',
      duration: _durationFrom(
        _meta(html, ['og:video:duration', 'video:duration']),
      ),
      platform: VideoPlatform.generic,
      qualities: QualityHelper.sortedByQuality([
        for (var index = 0; index < videos.length; index++)
          VideoQualityOption.video(
            id: index == 0 ? 'gen_og_$id' : 'gen_video_${index + 1}_$id',
            // Several videos on one page are separate clips, not qualities
            // of one, so each is its own download.
            mediaId: videos.length == 1 ? null : 'gen_video_${index + 1}_$id',
            label: videos.length == 1
                ? const EmbeddedVideo()
                : VideoIndex(index + 1),
            quality: videos.length == 1 && height != null
                ? '${height}p'
                : 'Original',
            format: _formatOf(videos[index], fallback: 'mp4'),
            downloadUrl: videos[index],
          ),
        if (media.audio.isNotEmpty)
          VideoQualityOption(
            id: 'gen_audio_$id',
            label: const OriginalAudio(),
            quality: 'Audio',
            format: _formatOf(media.audio.first, fallback: 'mp3'),
            downloadUrl: media.audio.first,
            kind: MediaKind.audio,
          ),
        for (var index = 0; index < images.length; index++)
          VideoQualityOption.image(
            id: index == 0 ? 'gen_image_$id' : 'gen_image_${index + 1}_$id',
            mediaId: images.length == 1 ? null : 'gen_image_${index + 1}_$id',
            label: ImageIndex(index + 1),
            quality: 'Original',
            format: MediaFormatHelper.inferImageFormat(images[index]),
            downloadUrl: images[index],
            thumbnailUrl: images[index],
          ),
      ]),
    );
  }

  /// A gallery page can list hundreds of pictures; the picker stays usable.
  static const int _maxPageImages = 30;

  /// Walks JSON-LD for the media schema.org says a page is about.
  ///
  /// Only objects that are themselves media count. An `Article.image` or an
  /// `Organization.logo` is decoration, and offering it as the page's media
  /// would be wrong more often than right.
  void _readLinkedData(dynamic value, _PageMedia media) {
    if (value is List) {
      for (final item in value) {
        _readLinkedData(item, media);
      }
      return;
    }
    if (value is! Map<String, dynamic>) return;

    final type = value['@type'];
    final types = type is List ? type.map((t) => '$t') : ['$type'];
    final content = value['contentUrl'];
    if (content is String) {
      if (types.contains('VideoObject')) media.addVideo(content);
      if (types.contains('AudioObject')) media.addAudio(content);
      if (types.contains('ImageObject')) media.addImage(content);
    }
    for (final child in value.values) {
      _readLinkedData(child, media);
    }
  }

  String _formatOf(String url, {required String fallback}) =>
      _directMediaFormat(Uri.parse(url)) ?? fallback;

  /// Every value of a `<meta>` key, in page order. A gallery repeats
  /// `og:image` once per picture.
  Iterable<String> _metaAll(String html, String key) sync* {
    final patterns = _patternsFor(key);
    final seen = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final value = match.group(1);
        if (value == null || value.isEmpty) continue;
        final decoded = decodeHtmlEntities(value);
        if (seen.add(decoded)) yield decoded;
      }
    }
  }

  static final RegExp _mediaTag = RegExp(
    r'<(video|audio)\b([^>]*)>([\s\S]*?)</\1\s*>',
    caseSensitive: false,
  );
  static final RegExp _sourceTag = RegExp(
    r'<source\b([^>]*)>',
    caseSensitive: false,
  );
  static final RegExp _ldJson = RegExp(
    r'''<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  );
  static final Map<String, RegExp> _attributePatterns = {};

  /// The value of [name] in a tag's attribute text, quoted either way or bare.
  String? _attribute(String attributes, String name) {
    final pattern = _attributePatterns.putIfAbsent(
      name,
      () => RegExp(
        '(?:^|\\s)$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s"\'>]+))',
        caseSensitive: false,
      ),
    );
    final match = pattern.firstMatch(attributes);
    final value = match?.group(1) ?? match?.group(2) ?? match?.group(3);
    return value == null || value.isEmpty ? null : decodeHtmlEntities(value);
  }

  /// Reads a `<meta>` tag's content, tolerating either attribute order
  /// (`property` before `content` or the reverse) and `name=` instead of
  /// `property=`.
  String? _meta(String html, List<String> keys) {
    for (final key in keys) {
      final patterns = _patternsFor(key);
      final match =
          patterns[0].firstMatch(html) ?? patterns[1].firstMatch(html);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) return decodeHtmlEntities(value);
    }
    return null;
  }

  /// Meta keys come from the caller, so the pair of patterns per key is cached
  /// rather than recompiled on every page.
  static final Map<String, List<RegExp>> _metaPatterns = {};

  static List<RegExp> _patternsFor(
    String key,
  ) => _metaPatterns.putIfAbsent(key, () {
    final escaped = RegExp.escape(key);
    return [
      RegExp(
        '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]*content=["\']([^"\']*)["\']',
        caseSensitive: false,
      ),
      RegExp(
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$escaped["\']',
        caseSensitive: false,
      ),
    ];
  });

  static final RegExp _htmlTitle = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );

  String? _title(String html) {
    final raw = _htmlTitle.firstMatch(html)?.group(1)?.trim();
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
}

/// The media a page declares, resolved against the page's own address and
/// free of duplicates, in the order it was found.
class _PageMedia {
  _PageMedia(this._page);

  final Uri _page;
  final videos = <String>{};
  final audio = <String>{};
  final images = <String>{};

  /// A video or audio was declared, but only as a stream playlist.
  var sawStream = false;

  bool get isEmpty => videos.isEmpty && audio.isEmpty && images.isEmpty;

  void addVideo(String? url) => _add(videos, url, playable: true);
  void addAudio(String? url) => _add(audio, url, playable: true);
  void addImage(String? url) => _add(images, url, playable: false);

  /// [url] as an absolute http(s) address, or null when it is not one.
  ///
  /// Declared URLs are often protocol-relative or site-relative. `blob:` and
  /// `data:` addresses only mean something inside the page that made them.
  String? resolve(String? url) {
    final trimmed = url?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final Uri resolved;
    try {
      resolved = _page.resolve(trimmed);
    } catch (_) {
      return null;
    }
    if (resolved.scheme != 'http' && resolved.scheme != 'https') return null;
    return resolved.toString();
  }

  /// The one of [urls] to download: the first in a widely playable format,
  /// else the first that is a file at all.
  String? preferred(List<String?> urls, List<String> extensions) {
    String? fallback;
    for (final url in urls) {
      final resolved = resolve(url);
      if (resolved == null) continue;
      final path = Uri.parse(resolved).path.toLowerCase();
      if (_isPlaylist(path)) {
        sawStream = true;
        continue;
      }
      if (extensions.any(path.endsWith)) return resolved;
      fallback ??= resolved;
    }
    return fallback;
  }

  // HLS and DASH playlists list hundreds of segments; there is no single
  // file behind them to download.
  static bool _isPlaylist(String path) =>
      path.endsWith('.m3u8') || path.endsWith('.mpd');

  void _add(Set<String> target, String? url, {required bool playable}) {
    final resolved = resolve(url);
    if (resolved == null) return;
    if (playable && _isPlaylist(Uri.parse(resolved).path.toLowerCase())) {
      sawStream = true;
      return;
    }
    target.add(resolved);
  }
}
