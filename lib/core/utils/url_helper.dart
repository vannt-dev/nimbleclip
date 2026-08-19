import '../../models/video_platform.dart';

class UrlHelper {
  /// Host suffixes owned by each platform, including the CDN and short-link
  /// domains that redirect into it.
  static const Map<VideoPlatform, List<String>> _platformHosts = {
    VideoPlatform.youtube: [
      'youtube.com',
      'youtu.be',
      'youtube-nocookie.com',
      'm.youtube.com',
    ],
    VideoPlatform.tiktok: ['tiktok.com', 'douyin.com'],
    VideoPlatform.facebook: ['facebook.com', 'fb.watch', 'fb.com', 'fb.me'],
    VideoPlatform.twitter: ['twitter.com', 'x.com', 't.co'],
    VideoPlatform.instagram: ['instagram.com', 'instagr.am', 'ig.me'],
  };

  static String extractCleanUrl(String text) {
    if (text.isEmpty) return '';

    // Pull the link out of potentially long shared text ("Check this out …").
    final urlRegex = RegExp(r'https?://[^\s<>"]+');
    final match = urlRegex.firstMatch(text);
    if (match != null) {
      // Trailing punctuation is almost always sentence punctuation, not URL.
      return (match.group(0) ?? '').trim().replaceAll(RegExp(r'[.,;!)]+$'), '');
    }
    return text.trim();
  }

  /// Host of [url], lowercased and without a `www.` prefix. Empty when the URL
  /// cannot be parsed.
  static String hostOf(String url) {
    try {
      final host = Uri.parse(url.trim()).host.toLowerCase();
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
  }

  /// True when [host] is [candidate] or a subdomain of it. Matching on the host
  /// rather than the whole URL stops `https://evil.com/?next=youtube.com` from
  /// being routed to the YouTube extractor.
  static bool hostMatches(String host, String candidate) =>
      host == candidate || host.endsWith('.$candidate');

  static VideoPlatform detectPlatform(String url) {
    final host = hostOf(url);
    if (host.isEmpty) return VideoPlatform.generic;

    for (final entry in _platformHosts.entries) {
      for (final candidate in entry.value) {
        if (hostMatches(host, candidate)) return entry.key;
      }
    }
    return VideoPlatform.generic;
  }

  static bool isValidVideoUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url.trim());
      return uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// True when the link is a short form whose real destination is only known
  /// after following the redirect.
  static bool isShortLink(String url) {
    final host = hostOf(url);
    const shortHosts = [
      't.co',
      'fb.watch',
      'fb.me',
      'vm.tiktok.com',
      'vt.tiktok.com',
      'youtu.be',
      'instagr.am',
      'ig.me',
    ];
    return shortHosts.any((candidate) => hostMatches(host, candidate));
  }
}
