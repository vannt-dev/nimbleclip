import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/utils/http_helper.dart';

/// Thrown when the service could not be consulted at all, as opposed to
/// answering that it found nothing. The caller reports the two differently:
/// an unanswered request leaves the photo count unknown, while an empty answer
/// is an answer.
class FacebookFallbackUnavailable implements Exception {
  final String reason;

  const FacebookFallbackUnavailable(this.reason);

  @override
  String toString() => 'FacebookFallbackUnavailable: $reason';
}

abstract interface class FacebookFallbackClient {
  /// Throws [FacebookFallbackUnavailable] when the service did not answer.
  /// An empty list means it answered and found nothing.
  Future<List<String>> extractImageUrls(String postUrl);
}

class ToolspyFacebookFallbackClient implements FacebookFallbackClient {
  const ToolspyFacebookFallbackClient();

  static const String _endpoint =
      'https://toolspy.net/api/facebook-image-extract/';
  static const Set<String> _hosts = {'toolspy.net', 'www.toolspy.net'};

  @override
  Future<List<String>> extractImageUrls(String postUrl) async {
    // The service has moved its API between the bare domain and the www host
    // twice, each time answering the other with a redirect, and a POST does
    // not follow redirects: every album shrank to its cover photo until the
    // address here was changed. So the redirect is followed by hand, once,
    // and only between the service's own two hosts.
    var response = await _post(_endpoint, postUrl);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      final moved = _movedTo(response);
      if (moved != null) response = await _post(moved, postUrl);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FacebookFallbackUnavailable('status ${response.statusCode}');
    }

    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } catch (error) {
      throw FacebookFallbackUnavailable('unreadable payload: $error');
    }
    if (payload is! Map<String, dynamic> || payload['images'] is! List) {
      throw const FacebookFallbackUnavailable('payload carried no image list');
    }
    return (payload['images'] as List)
        .map((value) => value.toString())
        .toList();
  }

  Future<http.Response> _post(String endpoint, String postUrl) =>
      ExtractorHttp.postWithRetry(
        endpoint,
        service: 'Toolspy',
        body: jsonEncode({'url': postUrl}),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      );

  /// Where a redirect answer points, when that is one of the service's own
  /// hosts. It names the address in a header, in its body, or in both.
  static String? _movedTo(http.Response response) {
    var target = response.headers['location'];
    if (target == null || target.isEmpty) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) target = body['redirect']?.toString();
      } catch (_) {
        // No readable body: there is nowhere to follow to.
      }
    }
    final uri = Uri.tryParse(target ?? '');
    if (uri == null || uri.scheme != 'https' || !_hosts.contains(uri.host)) {
      return null;
    }
    return uri.toString();
  }
}
