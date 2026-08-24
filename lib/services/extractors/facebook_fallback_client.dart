import 'dart:convert';

import '../../core/utils/http_helper.dart';

abstract interface class FacebookFallbackClient {
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
      return const [];
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['images'] is! List) {
      return const [];
    }
    return (payload['images'] as List)
        .map((value) => value.toString())
        .toList();
  }
}
