import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import 'cors_helper.dart';

/// HTTP entry point for the extractors: applies the platform-appropriate
/// headers, routes through the CORS proxy on Web, and enforces a timeout.
///
/// Browsers silently drop (or throw on) several request headers — `User-Agent`
/// and anything `Sec-*` among them — so those are translated or stripped rather
/// than sent verbatim.
class ExtractorHttp {
  static const Duration defaultTimeout = Duration(seconds: 15);
  static final http.Client _client = http.Client();

  @visibleForTesting
  static Future<http.Response> Function(Uri uri, Map<String, String> headers)?
  getOverride;

  @visibleForTesting
  static Future<http.Response> Function(
    Uri uri,
    Map<String, String> headers,
    Object? body,
  )?
  postOverride;

  @visibleForTesting
  static Future<http.Response> Function(Uri uri, Map<String, String> headers)?
  headOverride;

  static bool get isUsingOverrides =>
      getOverride != null || postOverride != null || headOverride != null;

  /// Lets extractors keep optional network fallbacks deterministic in tests
  /// without reaching into the test-only callback itself.
  static bool get hasPostOverride => postOverride != null;

  @visibleForTesting
  static void resetOverrides() {
    getOverride = null;
    postOverride = null;
    headOverride = null;
  }

  /// Facebook answers 400 to a page request that claims a browser User-Agent
  /// but omits the `Sec-Fetch-*` headers a browser always sends on a top-level
  /// navigation, which also swallows the redirect a `/share/…` link depends
  /// on. Sending them makes the request self-consistent. Observed on
  /// `/share/r/`, `/share/p/` and `/reel/`, all 400 without and 200 with.
  static const Map<String, String> _navigationHeaders = {
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Dest': 'document',
  };

  static Map<String, String> buildHeaders({
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? extra,
    bool navigation = true,
  }) {
    final headers = <String, String>{
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
      if (navigation) ..._navigationHeaders,
      ...?extra,
    };

    if (kIsWeb) {
      headers.removeWhere(
        (key, _) =>
            key.toLowerCase().startsWith('sec-') ||
            key.toLowerCase() == 'user-agent',
      );
      headers[CorsHelper.userAgentHeader] = userAgent;
    } else {
      headers['User-Agent'] = userAgent;
    }
    return headers;
  }

  static Future<http.Response> get(
    String url, {
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) {
    final uri = Uri.parse(CorsHelper.wrap(url));
    final requestHeaders = buildHeaders(userAgent: userAgent, extra: headers);
    final override = getOverride;
    if (override != null) return override(uri, requestHeaders);
    return _client.get(uri, headers: requestHeaders).timeout(timeout);
  }

  static Future<http.Response> head(
    String url, {
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) {
    // A HEAD probe is not a navigation — no browser ever sends one — and its
    // only reader is the Content-Type of a possible direct media file.
    final uri = Uri.parse(CorsHelper.wrap(url));
    final requestHeaders = buildHeaders(
      userAgent: userAgent,
      extra: headers,
      navigation: false,
    );
    final override = headOverride;
    if (override != null) return override(uri, requestHeaders);
    return _client.head(uri, headers: requestHeaders).timeout(timeout);
  }

  static Future<http.Response> post(
    String url, {
    Object? body,
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) {
    final uri = Uri.parse(CorsHelper.wrap(url));
    // The POST targets a JSON API, not a document navigation.
    final requestHeaders = buildHeaders(
      userAgent: userAgent,
      extra: headers,
      navigation: false,
    );
    final override = postOverride;
    if (override != null) return override(uri, requestHeaders, body);
    return _client
        .post(uri, headers: requestHeaders, body: body)
        .timeout(timeout);
  }

  static Future<http.Response> getWithRetry(
    String url, {
    String service = 'external service',
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
    int maxAttempts = 2,
  }) => _withRetry(
    service,
    () => get(url, userAgent: userAgent, headers: headers, timeout: timeout),
    maxAttempts,
  );

  static Future<http.Response> postWithRetry(
    String url, {
    String service = 'external service',
    Object? body,
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
    int maxAttempts = 2,
  }) => _withRetry(
    service,
    () => post(
      url,
      body: body,
      userAgent: userAgent,
      headers: headers,
      timeout: timeout,
    ),
    maxAttempts,
  );

  static Future<http.Response> _withRetry(
    String service,
    Future<http.Response> Function() request,
    int maxAttempts,
  ) async {
    // Test overrides describe one deterministic exchange. Replaying them can
    // hide fixture mistakes and unexpectedly change call counts.
    final attempts = isUsingOverrides ? 1 : maxAttempts.clamp(1, 3);
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final response = await request();
        final retryable =
            response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500;
        if (!retryable || attempt == attempts) return response;
        if (kDebugMode) {
          debugPrint(
            '$service returned ${response.statusCode}; retrying ($attempt/$attempts)',
          );
        }
      } catch (error) {
        lastError = error;
        if (attempt == attempts) rethrow;
        if (kDebugMode) {
          debugPrint(
            '$service request failed; retrying ($attempt/$attempts): $error',
          );
        }
      }
      await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
    }
    throw lastError ?? StateError('$service request failed');
  }

  /// Expands a short link to its final destination.
  ///
  /// On native platforms `package:http` follows redirects and reports the final
  /// URL on the response. In a browser the redirect chain is opaque, so the
  /// proxy's `/resolve` endpoint reports it instead. Returns [url] unchanged if
  /// resolution fails — callers should treat that as "not a short link".
  ///
  /// Expanding the link on a native platform downloads the destination page in
  /// full, so [page] carries that response for a caller whose next act is to
  /// fetch the very same URL. It is null whenever the body cannot stand in for
  /// a fresh request: on Web, where the proxy reports the URL and never
  /// fetches the page, and for an empty or failed response, which tells the
  /// caller nothing that re-requesting would not.
  static Future<({String url, http.Response? page})> resolveRedirects(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (kIsWeb) {
        final response = await _client
            .get(CorsHelper.resolveUri(url))
            .timeout(timeout);
        if (response.statusCode != 200) return (url: url, page: null);
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final resolved = json['url']?.toString();
        return (
          url: (resolved != null && resolved.isNotEmpty) ? resolved : url,
          page: null,
        );
      }

      // Keep redirect handling deterministic in extractor fixture tests while
      // preserving package:http's automatic redirect behavior in production.
      final uri = Uri.parse(url);
      final override = getOverride;
      final response = override != null
          ? await override(uri, buildHeaders())
          : await _client.get(uri, headers: buildHeaders()).timeout(timeout);
      final usable = response.statusCode < 400 && response.body.isNotEmpty;
      return (
        url: response.request?.url.toString() ?? url,
        page: usable ? response : null,
      );
    } catch (_) {
      return (url: url, page: null);
    }
  }
}
