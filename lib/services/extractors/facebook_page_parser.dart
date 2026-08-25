import 'dart:convert';

import '../../core/utils/media_url_helper.dart';
import '../../core/utils/text_unescape.dart';

class FacebookPageParser {
  const FacebookPageParser();

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
    for (final key in const [
      'og:video:secure_url',
      'og:video:url',
      'og:video',
    ]) {
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
      if (value != null && value.isNotEmpty) {
        return MediaUrlHelper.decode(value);
      }
    }
    return null;
  }

  String? videoId(String html) =>
      RegExp(r'"video_id"\s*:\s*"(\d+)"').firstMatch(html)?.group(1) ??
      RegExp(r'"videoId"\s*:\s*"(\d+)"').firstMatch(html)?.group(1);

  String title(String html) {
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

    final decoded = decodeHtmlEntities(
      decodeJsonEscapes(rawTitle),
    ).replaceAll(RegExp(r'\s*\|\s*Facebook\s*$'), '').trim();
    return decoded.isEmpty ? 'Facebook Video' : decoded;
  }

  String? stringField(String html, String key) {
    final value = RegExp('"$key":"([^"]{1,400})"').firstMatch(html)?.group(1);
    return value == null ? null : decodeJsonEscapes(value);
  }

  String? owner(String html) {
    final value =
        RegExp(r'"owner":\{[^}]*"name":"([^"]+)"').firstMatch(html)?.group(1) ??
        RegExp(r'"ownerName":"([^"]+)"').firstMatch(html)?.group(1);
    return value == null ? null : decodeJsonEscapes(value);
  }

  String? thumbnail(String html) {
    final raw =
        RegExp(
          r'"preferred_thumbnail":\{"image":\{"uri":"([^"]+)"',
        ).firstMatch(html)?.group(1) ??
        RegExp(
          r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"',
        ).firstMatch(html)?.group(1);
    return raw == null ? null : MediaUrlHelper.decode(raw);
  }

  Duration? duration(String html) {
    final milliseconds = int.tryParse(
      RegExp(r'"playable_duration_in_ms":(\d+)').firstMatch(html)?.group(1) ??
          '',
    );
    if (milliseconds != null && milliseconds > 0) {
      return Duration(milliseconds: milliseconds);
    }
    final seconds = int.tryParse(
      RegExp(r'"video_duration":(\d+)').firstMatch(html)?.group(1) ?? '',
    );
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }

  List<String> photoUrls(String html) {
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

    final scripts = RegExp(
      r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
      caseSensitive: false,
    ).allMatches(html);
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
