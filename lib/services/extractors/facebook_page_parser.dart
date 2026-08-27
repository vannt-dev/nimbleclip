import 'dart:convert';

import '../../core/utils/media_url_helper.dart';
import '../../core/utils/text_unescape.dart';
import 'parse_offloading.dart';

/// Isolate entry point for [FacebookPageParser.photoUrlsAsync]. Must be
/// top-level so it can be sent across an isolate boundary.
List<String> _facebookPhotoUrls(String html) =>
    const FacebookPageParser().photoUrls(html);

/// Patterns are hoisted to statics because `RegExp` compiles its pattern on
/// construction and Dart caches nothing between calls. Building them inside the
/// methods recompiled roughly twenty expressions on every extraction, each of
/// which then runs against a multi-megabyte page.
class FacebookPageParser {
  const FacebookPageParser();

  static final List<RegExp> _openGraphVideoPatterns = [
    for (final key in const ['og:video:secure_url', 'og:video:url', 'og:video'])
      for (final template in [
        '<meta[^>]+(?:property|name)=["\']@["\'][^>]*content=["\']([^"\']*)["\']',
        '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']@["\']',
      ])
        RegExp(
          template.replaceFirst('@', RegExp.escape(key)),
          caseSensitive: false,
        ),
  ];

  static final RegExp _videoIdSnake = RegExp(r'"video_id"\s*:\s*"(\d+)"');
  static final RegExp _videoIdCamel = RegExp(r'"videoId"\s*:\s*"(\d+)"');
  static final RegExp _ogTitle = RegExp(
    r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"',
  );
  static final RegExp _htmlTitle = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _facebookSuffix = RegExp(r'\s*\|\s*Facebook\s*$');
  static final RegExp _ownerName = RegExp(r'"owner":\{[^}]*"name":"([^"]+)"');
  static final RegExp _ownerNameFlat = RegExp(r'"ownerName":"([^"]+)"');
  static final RegExp _preferredThumbnail = RegExp(
    r'"preferred_thumbnail":\{"image":\{"uri":"([^"]+)"',
  );
  static final RegExp _ogImage = RegExp(
    r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
  );
  static final RegExp _durationMs = RegExp(r'"playable_duration_in_ms":(\d+)');
  static final RegExp _durationSeconds = RegExp(r'"video_duration":(\d+)');
  static final RegExp _jsonScripts = RegExp(
    r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
    caseSensitive: false,
  );

  /// `stringField` takes the key from the caller, so its pattern cannot be a
  /// plain static. The set of keys used is small and fixed at each call site,
  /// so caching by key keeps the compile cost to once per key per process.
  static final Map<String, RegExp> _stringFieldPatterns = {};

  String? firstMediaUrl(String html, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) {
        final decoded = MediaUrlHelper.decode(value);
        if (MediaUrlHelper.isHttp(decoded)) return decoded;
      }
    }
    return null;
  }

  /// Reads the standard Open Graph video fields used by Facebook's lightweight
  /// share landing pages. Attribute order varies between page variants.
  String? openGraphVideo(String html) {
    for (final pattern in _openGraphVideoPatterns) {
      final value = pattern.firstMatch(html)?.group(1);
      if (value != null && value.isNotEmpty) {
        return MediaUrlHelper.decode(value);
      }
    }
    return null;
  }

  String? videoId(String html) =>
      _videoIdSnake.firstMatch(html)?.group(1) ??
      _videoIdCamel.firstMatch(html)?.group(1);

  String title(String html) {
    final ogTitle = _ogTitle.firstMatch(html)?.group(1);
    final rawTitle = ogTitle ?? _htmlTitle.firstMatch(html)?.group(1);
    if (rawTitle == null || rawTitle.trim().isEmpty) return 'Facebook Video';

    final decoded = decodeHtmlEntities(
      decodeJsonEscapes(rawTitle),
    ).replaceAll(_facebookSuffix, '').trim();
    return decoded.isEmpty ? 'Facebook Video' : decoded;
  }

  String? stringField(String html, String key) {
    final pattern = _stringFieldPatterns.putIfAbsent(
      key,
      () => RegExp('"$key":"([^"]{1,400})"'),
    );
    final value = pattern.firstMatch(html)?.group(1);
    return value == null ? null : decodeJsonEscapes(value);
  }

  String? owner(String html) {
    final value =
        _ownerName.firstMatch(html)?.group(1) ??
        _ownerNameFlat.firstMatch(html)?.group(1);
    return value == null ? null : decodeJsonEscapes(value);
  }

  String? thumbnail(String html) {
    final raw =
        _preferredThumbnail.firstMatch(html)?.group(1) ??
        _ogImage.firstMatch(html)?.group(1);
    return raw == null ? null : MediaUrlHelper.decode(raw);
  }

  Duration? duration(String html) {
    final milliseconds = int.tryParse(
      _durationMs.firstMatch(html)?.group(1) ?? '',
    );
    if (milliseconds != null && milliseconds > 0) {
      return Duration(milliseconds: milliseconds);
    }
    final seconds = int.tryParse(
      _durationSeconds.firstMatch(html)?.group(1) ?? '',
    );
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }

  /// Same scan as [photoUrls], moved off the UI isolate for pages large enough
  /// to be worth the hand-off. This is the heaviest step in a Facebook
  /// extraction: it decodes and walks every inline JSON block on the page.
  Future<List<String>> photoUrlsAsync(String html) => parseOffMainIsolate(
    _facebookPhotoUrls,
    html,
    debugLabel: 'facebook.photoUrls',
  );

  List<String> photoUrls(String html) {
    final urls = <String>[];
    final seen = <String>{};

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
      if (seen.add(best)) urls.add(best);
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
          visit(
            entry.value,
            inSubattachments:
                inSubattachments || entry.key == 'all_subattachments',
          );
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child, inSubattachments: inSubattachments);
        }
      }
    }

    final scripts = _jsonScripts.allMatches(html);
    for (final script in scripts) {
      try {
        visit(jsonDecode(decodeHtmlEntities(script.group(1) ?? '')));
      } catch (_) {
        // Ignore non-JSON bootloader scripts.
      }
    }
    return urls;
  }
}
