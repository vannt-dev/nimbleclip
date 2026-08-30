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

  static final RegExp _singleUrl = RegExp(r'https?://[^\s<>"]+');
  static final RegExp _multipleUrls = RegExp(r'''https?://[^\s<>"']+''');
  static final RegExp _trailingPunctuation = RegExp(r'[.,;!)]+$');
  // The type segment names what was shared — `r` a reel, `v` a video, `p` a
  // post — but Facebook also emits the bare `/share/<token>/`, which carries
  // no segment at all and is the form its Share action produces for a post.
  static final RegExp _facebookSharePath = RegExp(
    r'^/share/(?:(?:r|v|p)/)?[^/]+/?$',
  );

  static String extractCleanUrl(String text) {
    if (text.isEmpty) return '';

    // Pull the link out of potentially long shared text ("Check this out …").
    final match = _singleUrl.firstMatch(text);
    if (match != null) {
      // Trailing punctuation is almost always sentence punctuation, not URL.
      return (match.group(0) ?? '').trim().replaceAll(_trailingPunctuation, '');
    }
    return text.trim();
  }

  static List<String> extractUrls(String text) {
    final seen = <String>{};
    final urls = <String>[];
    for (final match in _multipleUrls.allMatches(text)) {
      // Trim once and reuse: the earlier version recomputed this for the
      // duplicate check and again for the value it kept.
      final url = (match.group(0) ?? '').replaceAll(_trailingPunctuation, '');
      if (seen.add(url) && isValidVideoUrl(url)) urls.add(url);
    }
    return List.unmodifiable(urls);
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
    if (shortHosts.any((candidate) => hostMatches(host, candidate))) {
      return true;
    }

    // Facebook's mobile Share action now commonly emits same-host redirect
    // links instead of fb.watch links. The path carries only an opaque token,
    // so it must be expanded before a video or post can be extracted.
    if (hostMatches(host, 'facebook.com')) {
      final path = Uri.tryParse(url.trim())?.path.toLowerCase() ?? '';
      return _facebookSharePath.hasMatch(path);
    }
    return false;
  }
}
