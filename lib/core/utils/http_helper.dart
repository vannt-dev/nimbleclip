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

  @visibleForTesting
  static void resetOverrides() {
    getOverride = null;
    postOverride = null;
    headOverride = null;
  }

  static Map<String, String> buildHeaders({
    String userAgent = AppConstants.defaultUserAgent,
    Map<String, String>? extra,
  }) {
    final headers = <String, String>{
      'Accept': '*/*',
      'Accept-Language': 'en-US,en;q=0.9',
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
    final uri = Uri.parse(CorsHelper.wrap(url));
    final requestHeaders = buildHeaders(userAgent: userAgent, extra: headers);
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
    final requestHeaders = buildHeaders(userAgent: userAgent, extra: headers);
    final override = postOverride;
    if (override != null) return override(uri, requestHeaders, body);
    return _client
        .post(uri, headers: requestHeaders, body: body)
        .timeout(timeout);
  }

  /// Expands a short link to its final destination.
  ///
  /// On native platforms `package:http` follows redirects and reports the final
  /// URL on the response. In a browser the redirect chain is opaque, so the
  /// proxy's `/resolve` endpoint reports it instead. Returns [url] unchanged if
  /// resolution fails — callers should treat that as "not a short link".
  static Future<String> resolveRedirects(
    String url, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (kIsWeb) {
        final response = await _client
            .get(CorsHelper.resolveUri(url))
            .timeout(timeout);
        if (response.statusCode != 200) return url;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final resolved = json['url']?.toString();
        return (resolved != null && resolved.isNotEmpty) ? resolved : url;
      }

      final response = await _client
          .get(Uri.parse(url), headers: buildHeaders())
          .timeout(timeout);
      return response.request?.url.toString() ?? url;
    } catch (_) {
      return url;
    }
  }
}
