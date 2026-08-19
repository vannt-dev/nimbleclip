import 'package:flutter/foundation.dart';

/// Routes outbound requests through the local dev proxy (`server.js`) when the
/// app runs in a browser, where cross-origin requests to the video platforms are
/// blocked by CORS.
class CorsHelper {
  static const String proxyPath = '/cors-proxy';
  static const String resolvePath = '/resolve';

  /// Header the proxy reads as the upstream `User-Agent`. Browsers refuse to let
  /// scripts set `User-Agent` directly, so the value is smuggled through a
  /// custom header that the proxy renames.
  static const String userAgentHeader = 'X-Proxy-User-Agent';

  static bool get isProxied => kIsWeb;

  /// Wraps a URL with the CORS proxy when running on Web.
  ///
  /// [downloadFileName] makes the proxy respond with a
  /// `Content-Disposition: attachment` header, which is the only way a browser
  /// saves a cross-origin video instead of navigating to it.
  static String wrap(String url, {String? downloadFileName}) {
    if (!kIsWeb) return url;
    if (url.startsWith(proxyPath)) return url;

    final buffer = StringBuffer('$proxyPath?url=${Uri.encodeComponent(url)}');
    if (downloadFileName != null && downloadFileName.isNotEmpty) {
      buffer.write('&filename=${Uri.encodeComponent(downloadFileName)}');
    }
    return buffer.toString();
  }

  static Uri wrapUri(Uri uri, {String? downloadFileName}) {
    if (!kIsWeb) return uri;
    return Uri.parse(wrap(uri.toString(), downloadFileName: downloadFileName));
  }

  /// Endpoint that follows redirects server-side and reports the final URL.
  /// Used to expand short links (t.co, vm.tiktok.com, fb.watch) on Web, where
  /// the client cannot observe the redirect chain.
  static Uri resolveUri(String url) =>
      Uri.parse('$resolvePath?url=${Uri.encodeComponent(url)}');
}
