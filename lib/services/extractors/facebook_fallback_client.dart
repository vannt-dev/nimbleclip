import 'dart:convert';

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

  @override
  Future<List<String>> extractImageUrls(String postUrl) async {
    final response = await ExtractorHttp.postWithRetry(
      'https://toolspy.net/api/facebook-image-extract/',
      service: 'Toolspy',
      body: jsonEncode({'url': postUrl}),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
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
}
