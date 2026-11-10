import 'dart:io';

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

  // A share link is only useful for where it lands. The answer must name the
  // page at the end of the redirects, not the link that was asked for.
  test('expanding a link reports the address the redirects end on', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path == '/share/abc') {
        response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/@someone/post/CODE1');
      } else {
        response.write('<html>post</html>');
      }
      await response.close();
    });
    final base = 'http://${server.address.host}:${server.port}';

    final resolved = await ExtractorHttp.resolveRedirects('$base/share/abc');

    expect(resolved.url, '$base/@someone/post/CODE1');
    expect(resolved.page?.body, '<html>post</html>');
  });

  // Some shorteners answer a browser with a page that sends it onward rather
  // than with a redirect, so the address has to be read out of that page.
  test('expanding a link follows a page that only forwards', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.write(
        '<head><noscript><META http-equiv="refresh" content="0;URL='
        'https://twitter.com/someone/status/123/video/1"></noscript></head>',
      );
      await request.response.close();
    });

    final resolved = await ExtractorHttp.resolveRedirects(
      'http://${server.address.host}:${server.port}/abc',
    );

    expect(resolved.url, 'https://twitter.com/someone/status/123/video/1');
    expect(resolved.page, isNull);
  });
}
