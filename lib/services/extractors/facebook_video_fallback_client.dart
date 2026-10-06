import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/text_unescape.dart';

/// A video an external service found behind a Facebook link.
class FacebookFallbackVideo {
  const FacebookFallbackVideo({
    required this.files,
    this.id,
    this.title,
    this.thumbnailUrl,
    this.duration,
  });

  /// The video at each quality the service has a file for, as it listed them.
  final List<({String quality, String url})> files;
  final String? id;
  final String? title;
  final String? thumbnailUrl;
  final Duration? duration;
}

/// Asks an external service for a Facebook video the anonymous web does not
/// show: a story, above all, which Facebook serves only to a logged-in reader.
abstract interface class FacebookVideoFallbackClient {
  /// Null when the service did not answer or found no video.
  Future<FacebookFallbackVideo?> find(String postUrl);
}

/// X2Download, which answers in the same shape as the service behind
/// `SnapInstaFallbackClient`: a token read off its landing page, then a search
/// that returns a fragment of HTML.
class X2DownloadFacebookFallbackClient implements FacebookVideoFallbackClient {
  const X2DownloadFacebookFallbackClient();

  static const String _landingPage =
      'https://x2download.com/en/download-video-facebook';
  static const String _search = 'https://x2download.com/api/ajaxSearch';

  static String? _cachedExpiry;
  static String? _cachedToken;

  static final RegExp _expiryPattern = RegExp(r'\bk_exp\s*=\s*"([^"]+)"');
  static final RegExp _tokenPattern = RegExp(r'\bk_token\s*=\s*"([^"]+)"');
  static final RegExp _row = RegExp(r'<tr[\s>][\s\S]*?</tr>');
  static final RegExp _quality = RegExp(
    r'''class=["']video-quality["'][^>]*>([^<]+)<''',
  );
  static final RegExp _link = RegExp(
    r'''<a[^>]+href=["'](https?://[^"']+)["']''',
  );
  static final RegExp _heading = RegExp(r'<h3[^>]*>([^<]+)</h3>');
  static final RegExp _videoId = RegExp(r'#(\d{6,})');
  static final RegExp _thumbnail = RegExp(
    r'''class=["']thumbnail["'][\s\S]*?<img[^>]+src=["'](https?://[^"']+)["']''',
  );
  static final RegExp _length = RegExp(
    r'<p>\s*(?:(\d+):)?(\d{1,2}):(\d{2})\s*</p>',
  );

  @override
  Future<FacebookFallbackVideo?> find(String postUrl) async {
    var expiry = _cachedExpiry;
    var token = _cachedToken;
    final expirySeconds = int.tryParse(expiry ?? '');
    final cacheValid =
        !ExtractorHttp.isUsingOverrides &&
        expirySeconds != null &&
        expirySeconds > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30 &&
        token != null;

    if (!cacheValid) {
      final landing = await ExtractorHttp.getWithRetry(
        _landingPage,
        service: 'X2Download',
        userAgent: AppConstants.defaultUserAgent,
      );
      if (landing.statusCode != 200) return null;
      expiry = _expiryPattern.firstMatch(landing.body)?.group(1);
      token = _tokenPattern.firstMatch(landing.body)?.group(1);
      if (!ExtractorHttp.isUsingOverrides) {
        _cachedExpiry = expiry;
        _cachedToken = token;
      }
    }
    if (expiry == null || token == null) return null;

    final response = await ExtractorHttp.postWithRetry(
      _search,
      service: 'X2Download',
      userAgent: AppConstants.defaultUserAgent,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'k_exp': expiry,
        'k_token': token,
        'q': postUrl,
        'lang': 'en',
        'web': 'x2download.com',
        'v': 'v2',
        'w': '',
      },
    );
    if (response.statusCode != 200) return null;

    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } catch (_) {
      return null;
    }
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      return null;
    }
    return parse(payload['data']?.toString() ?? '');
  }

  /// Reads the service's HTML answer. Null when it lists no file.
  ///
  /// A quality the service would have to convert first has a button rather
  /// than a link, and is left out: only files that already exist are offered.
  static FacebookFallbackVideo? parse(String html) {
    final files = <({String quality, String url})>[];
    final seen = <String>{};
    for (final row in _row.allMatches(html)) {
      final cells = row.group(0)!;
      final quality = _quality.firstMatch(cells)?.group(1)?.trim();
      final link = _link.firstMatch(cells)?.group(1);
      if (quality == null || link == null) continue;
      final url = _fileBehind(decodeHtmlEntities(link));
      if (seen.add(quality)) files.add((quality: quality, url: url));
    }
    if (files.isEmpty) return null;

    final heading = _heading.firstMatch(html)?.group(1)?.trim();
    final length = _length.firstMatch(html);
    final thumbnail = _thumbnail.firstMatch(html)?.group(1);
    return FacebookFallbackVideo(
      files: files,
      id: heading == null ? null : _videoId.firstMatch(heading)?.group(1),
      title: heading == null ? null : decodeHtmlEntities(heading),
      thumbnailUrl: thumbnail == null ? null : decodeHtmlEntities(thumbnail),
      duration: length == null
          ? null
          : Duration(
              hours: int.parse(length.group(1) ?? '0'),
              minutes: int.parse(length.group(2)!),
              seconds: int.parse(length.group(3)!),
            ),
    );
  }

  /// The service links to its own relay, with Facebook's address for the file
  /// inside a token. That address is used when it can be read: it is one hop
  /// fewer, and it does not stop working if the relay does.
  static String _fileBehind(String link) {
    final token = Uri.tryParse(link)?.queryParameters['token'];
    final parts = token?.split('.');
    if (parts == null || parts.length != 3) return link;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final url = claims is Map<String, dynamic> ? claims['url'] : null;
      return url is String && url.startsWith('https://') ? url : link;
    } catch (_) {
      return link;
    }
  }
}
