import 'package:flutter/foundation.dart';

class CorsHelper {
  /// Wraps a URL with CORS proxy if running on Web browser
  static String wrap(String url) {
    if (!kIsWeb) return url;
    if (url.startsWith('/cors-proxy') || url.contains('/cors-proxy?url=')) {
      return url;
    }
    // Use local proxy when running on web
    return '/cors-proxy?url=${Uri.encodeComponent(url)}';
  }

  /// Create a proxy URL that works in browser
  static Uri wrapUri(Uri uri) {
    if (!kIsWeb) return uri;
    return Uri.parse(wrap(uri.toString()));
  }
}
