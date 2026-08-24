import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';

abstract interface class InstagramFallbackClient {
  Future<String?> search(String postUrl);
}

class SnapInstaFallbackClient implements InstagramFallbackClient {
  const SnapInstaFallbackClient();

  static String? _cachedExpiry;
  static String? _cachedToken;

  @override
  Future<String?> search(String postUrl) async {
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
        'https://snap-insta.to/vi',
        service: 'SnapInsta',
        userAgent: AppConstants.defaultUserAgent,
      );
      if (landing.statusCode != 200) return null;
      expiry = RegExp(
        r'\bk_exp\s*=\s*"([^"]+)"',
      ).firstMatch(landing.body)?.group(1);
      token = RegExp(
        r'\bk_token\s*=\s*"([^"]+)"',
      ).firstMatch(landing.body)?.group(1);
      if (!ExtractorHttp.isUsingOverrides) {
        _cachedExpiry = expiry;
        _cachedToken = token;
      }
    }
    if (expiry == null || token == null) return null;

    final response = await ExtractorHttp.postWithRetry(
      'https://snap-insta.to/api/ajaxSearch',
      service: 'SnapInsta',
      userAgent: AppConstants.defaultUserAgent,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'k_exp': expiry,
        'k_token': token,
        'q': postUrl,
        't': 'media',
        'lang': 'vi',
        'v': 'v2',
      },
    );
    if (response.statusCode != 200) return null;

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic> || payload['status'] != 'ok') {
      return null;
    }
    final html = payload['data']?.toString() ?? '';
    return html.isEmpty ? null : html;
  }
}
