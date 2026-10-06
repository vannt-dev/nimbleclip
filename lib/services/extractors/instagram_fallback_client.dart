import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';

abstract interface class InstagramFallbackClient {
  Future<String?> search(String postUrl);
}

/// One site of the family of services that answer a search with a fragment of
/// HTML, after a token read off their landing page.
class _SearchService {
  _SearchService({
    required this.name,
    required this.landingPage,
    required this.search,
    required this.parameters,
  });

  final String name;
  final String landingPage;
  final String search;

  /// What this site's own page sends beside the token and the link.
  final Map<String, String> parameters;

  String? cachedExpiry;
  String? cachedToken;
}

class SnapInstaFallbackClient implements InstagramFallbackClient {
  const SnapInstaFallbackClient();

  // Tried in order. The second is there because the first cannot be reached
  // from every network: some providers answer its name with a loopback
  // address, and every story, highlight and reel that needs the service then
  // fails for everyone on them. Both return the same markup.
  static final List<_SearchService> _services = [
    _SearchService(
      name: 'SnapInsta',
      landingPage: 'https://snap-insta.to/vi',
      search: 'https://snap-insta.to/api/ajaxSearch',
      parameters: const {'t': 'media', 'lang': 'vi', 'v': 'v2'},
    ),
    _SearchService(
      name: 'X2Download',
      landingPage: 'https://x2download.com/en/download-video-facebook',
      search: 'https://x2download.com/api/ajaxSearch',
      parameters: const {
        'lang': 'en',
        'web': 'x2download.com',
        'v': 'v2',
        'w': '',
      },
    ),
  ];

  static final RegExp _expiryPattern = RegExp(r'\bk_exp\s*=\s*"([^"]+)"');
  static final RegExp _tokenPattern = RegExp(r'\bk_token\s*=\s*"([^"]+)"');

  @override
  Future<String?> search(String postUrl) async {
    Object? lastError;
    for (final service in _services) {
      try {
        final html = await _searchOn(service, postUrl);
        if (html != null) return html;
      } catch (error) {
        // Unreachable is a reason to ask the next one, not to give up.
        lastError = error;
      }
    }
    // Only when no service answered at all: the caller tells "could not ask"
    // apart from "asked and found nothing".
    if (lastError != null) {
      Error.throwWithStackTrace(lastError, StackTrace.current);
    }
    return null;
  }

  Future<String?> _searchOn(_SearchService service, String postUrl) async {
    var expiry = service.cachedExpiry;
    var token = service.cachedToken;
    final expirySeconds = int.tryParse(expiry ?? '');
    final cacheValid =
        !ExtractorHttp.isUsingOverrides &&
        expirySeconds != null &&
        expirySeconds > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 30 &&
        token != null;

    if (!cacheValid) {
      final landing = await ExtractorHttp.getWithRetry(
        service.landingPage,
        service: service.name,
        userAgent: AppConstants.defaultUserAgent,
      );
      if (landing.statusCode != 200) return null;
      expiry = _expiryPattern.firstMatch(landing.body)?.group(1);
      token = _tokenPattern.firstMatch(landing.body)?.group(1);
      if (!ExtractorHttp.isUsingOverrides) {
        service.cachedExpiry = expiry;
        service.cachedToken = token;
      }
    }
    if (expiry == null || token == null) return null;

    final response = await ExtractorHttp.postWithRetry(
      service.search,
      service: service.name,
      userAgent: AppConstants.defaultUserAgent,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'k_exp': expiry,
        'k_token': token,
        'q': postUrl,
        ...service.parameters,
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
