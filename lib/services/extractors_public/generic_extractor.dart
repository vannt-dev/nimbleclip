import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/http_helper.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';

/// Reads a link that is a media file, or a page that names its media in Open
/// Graph or Twitter Card metadata.
///
/// This is the whole of the public core's knowledge of the web: no site is
/// handled by name, no stream is followed, and a page that builds its player
/// in script is answered with "no video on this page".
class GenericExtractor extends BaseVideoExtractor {
  const GenericExtractor();

  static const _video = {'mp4', 'm4v', 'mov', 'webm', 'mkv'};
  static const _audio = {'mp3', 'm4a', 'aac', 'ogg', 'opus', 'wav', 'flac'};
  static const _image = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'avif'};

  @override
  VideoPlatform get platform => VideoPlatform.generic;

  @override
  bool canHandle(String url) => true;

  @override
  Future<VideoMetadata> extract(String url) async {
    final uri = Uri.parse(url);
    final named = _extensionOf(uri);
    if (named != null && _kindOf(named) != null) {
      return _single(url, uri, format: named, kind: _kindOf(named)!);
    }

    final http.Response response;
    try {
      response = await ExtractorHttp.get(url);
    } catch (_) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.linkAccessFailed),
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

    // A media file served from an address that does not say so.
    final type = (response.headers['content-type'] ?? '').toLowerCase();
    final served = _formatOfType(type);
    if (served != null) {
      return _single(url, uri, format: served, kind: _kindOf(served)!);
    }

    final page = _decode(response);
    // Many pages name an embeddable player as their video, which is a web
    // page: only a file counts, by its name or by the type the page declares.
    final videoType = _contents(page, const ['og:video:type']);
    final declaredVideo =
        videoType.isNotEmpty &&
        videoType.first.toLowerCase().startsWith('video/');
    final videos = _contents(page, const [
      'og:video:secure_url',
      'og:video:url',
      'og:video',
      'twitter:player:stream',
    ]).where((url) => _isFile(url, _video, declared: declaredVideo)).toList();
    final audioType = _contents(page, const ['og:audio:type']);
    final declaredAudio =
        audioType.isNotEmpty &&
        audioType.first.toLowerCase().startsWith('audio/');
    final audios = _contents(page, const [
      'og:audio:secure_url',
      'og:audio:url',
      'og:audio',
    ]).where((url) => _isFile(url, _audio, declared: declaredAudio)).toList();
    final images = _contents(page, const [
      'og:image:secure_url',
      'og:image:url',
      'og:image',
      'twitter:image',
    ]);
    if (videos.isEmpty && audios.isEmpty && images.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.genericNoVideo),
      );
    }

    final id = _idOf(url);
    final title = _contents(page, const ['og:title', 'twitter:title']);
    final site = _contents(page, const ['og:site_name']);
    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: title.isNotEmpty ? title.first : (_titleOf(page) ?? uri.host),
      author: site.isNotEmpty ? site.first : uri.host,
      coverUrl: images.isNotEmpty ? _absolute(uri, images.first) : '',
      platform: VideoPlatform.generic,
      qualities: [
        if (videos.isNotEmpty)
          VideoQualityOption.video(
            id: 'gen_og_$id',
            label: const EmbeddedVideo(),
            quality: 'Original',
            format: _extensionOf(Uri.parse(videos.first)) ?? 'mp4',
            downloadUrl: _absolute(uri, videos.first),
          ),
        if (audios.isNotEmpty)
          VideoQualityOption.audio(
            id: 'gen_audio_$id',
            label: const OriginalAudio(),
            quality: 'Audio',
            format: _extensionOf(Uri.parse(audios.first)) ?? 'mp3',
            downloadUrl: _absolute(uri, audios.first),
          ),
        // A page with a video names its poster as the image; offering the
        // poster as a second download would only be noise.
        if (videos.isEmpty && audios.isEmpty)
          VideoQualityOption.image(
            id: 'gen_image_$id',
            label: const ImageIndex(1),
            format: _extensionOf(Uri.parse(images.first)) ?? 'jpg',
            downloadUrl: _absolute(uri, images.first),
            thumbnailUrl: _absolute(uri, images.first),
          ),
      ],
    );
  }

  VideoMetadata _single(
    String url,
    Uri uri, {
    required String format,
    required MediaKind kind,
  }) {
    final id = _idOf(url);
    final name = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
    return VideoMetadata(
      id: id,
      originalUrl: url,
      title: Uri.decodeComponent(name),
      author: uri.host,
      coverUrl: kind == MediaKind.image ? url : '',
      platform: VideoPlatform.generic,
      qualities: [
        VideoQualityOption(
          id: 'gen_$id',
          label: switch (kind) {
            MediaKind.image => const ImageIndex(1),
            MediaKind.audio => const OriginalAudio(),
            MediaKind.video => const OriginalVideo(),
          },
          quality: 'Original',
          format: format,
          downloadUrl: url,
          thumbnailUrl: kind == MediaKind.image ? url : null,
          kind: kind,
        ),
      ],
    );
  }

  static MediaKind? _kindOf(String format) => _video.contains(format)
      ? MediaKind.video
      : _audio.contains(format)
      ? MediaKind.audio
      : _image.contains(format)
      ? MediaKind.image
      : null;

  static String? _extensionOf(Uri uri) {
    if (uri.pathSegments.isEmpty) return null;
    final name = uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return null;
    return name.substring(dot + 1).toLowerCase();
  }

  /// The format a Content-Type names, when it is one this extractor offers.
  static String? _formatOfType(String type) {
    final essence = type.split(';').first.trim();
    final slash = essence.indexOf('/');
    if (slash <= 0) return null;
    final family = essence.substring(0, slash);
    if (family != 'video' && family != 'audio' && family != 'image') {
      return null;
    }
    final format = switch (essence.substring(slash + 1)) {
      'mpeg' => family == 'audio' ? 'mp3' : null,
      'quicktime' => 'mov',
      'x-m4a' || 'mp4' when family == 'audio' => 'm4a',
      'jpeg' => 'jpg',
      final other => other,
    };
    return format != null && _kindOf(format) != null ? format : null;
  }

  /// Whether [url] is a media file of one of [formats]: by its extension, or,
  /// when it has none that says otherwise, because the page [declared] it one.
  /// A stream's playlist is not a file, and this core does not follow one.
  static bool _isFile(
    String url,
    Set<String> formats, {
    required bool declared,
  }) {
    final format = _extensionOf(Uri.tryParse(url) ?? Uri());
    if (format != null && formats.contains(format)) return true;
    return declared && format != 'm3u8' && format != 'mpd';
  }

  static String _absolute(Uri page, String reference) =>
      page.resolve(reference).toString();

  static String _idOf(String url) =>
      (url.hashCode & 0x7fffffff).toRadixString(16).padLeft(8, '0');

  static String _decode(http.Response response) {
    try {
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } catch (_) {
      return response.body;
    }
  }

  static final RegExp _meta = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
  static final RegExp _attribute = RegExp(
    r'''([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''',
  );
  static final RegExp _title = RegExp(
    r'<title[^>]*>([^<]*)</title>',
    caseSensitive: false,
  );

  /// The `content` of the page's meta tags named one of [names], in the order
  /// of [names].
  static List<String> _contents(String page, List<String> names) {
    final found = <String, String>{};
    for (final tag in _meta.allMatches(page)) {
      String? name;
      String? content;
      for (final attribute in _attribute.allMatches(tag.group(0)!)) {
        final value = attribute.group(2) ?? attribute.group(3) ?? '';
        switch (attribute.group(1)!.toLowerCase()) {
          case 'property' || 'name':
            name = value.toLowerCase();
          case 'content':
            content = _unescape(value);
        }
      }
      if (name != null && content != null && content.isNotEmpty) {
        found.putIfAbsent(name, () => content!);
      }
    }
    return [for (final name in names) ?found[name]];
  }

  static String? _titleOf(String page) {
    final title = _title.firstMatch(page)?.group(1)?.trim();
    return title == null || title.isEmpty ? null : _unescape(title);
  }

  static String _unescape(String text) => text
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
