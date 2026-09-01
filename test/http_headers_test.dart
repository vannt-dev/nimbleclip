import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/http_helper.dart';

/// Facebook rejects a page request that claims a browser User-Agent but omits
/// the `Sec-Fetch-*` headers every browser sends on a top-level navigation: it
/// answers 400 and never issues the redirect a `/share/…` link depends on.
/// Observed against `/share/r/`, `/share/p/` and `/reel/` links, all of which
/// return 200 once the navigation headers are present.
void main() {
  test('page requests carry browser navigation Sec-Fetch headers', () {
    final headers = ExtractorHttp.buildHeaders();

    expect(headers['Sec-Fetch-Site'], 'none');
    expect(headers['Sec-Fetch-Mode'], 'navigate');
    expect(headers['Sec-Fetch-Dest'], 'document');
  });

  test('an explicit header still overrides the navigation default', () {
    final headers = ExtractorHttp.buildHeaders(
      extra: const {'Sec-Fetch-Mode': 'cors'},
    );

    expect(headers['Sec-Fetch-Mode'], 'cors');
  });

  // The JSON calls to the fallback service and the HEAD probe for a direct
  // media file are not navigations, and claiming otherwise would describe the
  // request wrongly to every server that reads these headers.
  test('a request that is not a navigation sends no Sec-Fetch headers', () {
    final headers = ExtractorHttp.buildHeaders(navigation: false);

    expect(headers.keys.where((key) => key.startsWith('Sec-Fetch')), isEmpty);
    expect(headers['Accept'], '*/*');
  });
}
