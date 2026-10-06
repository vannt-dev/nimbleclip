import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/services/extractors/instagram_fallback_client.dart';

const _reel = 'https://www.instagram.com/reel/abc/';

http.Response _landing() =>
    http.Response('<script>k_exp="1"; k_token="token";</script>', 200);

http.Response _found(String html) =>
    http.Response(jsonEncode({'status': 'ok', 'data': html}), 200);

void main() {
  tearDown(ExtractorHttp.resetOverrides);

  test('asks the first service and stops when it answers', () async {
    final asked = <String>[];
    ExtractorHttp.getOverride = (uri, _) async {
      asked.add(uri.host);
      return _landing();
    };
    ExtractorHttp.postOverride = (uri, _, _) async {
      asked.add(uri.host);
      return _found('<a>first</a>');
    };

    final html = await const SnapInstaFallbackClient().search(_reel);

    expect(html, '<a>first</a>');
    expect(asked, ['snap-insta.to', 'snap-insta.to']);
  });

  test('asks the second when the first cannot be reached', () async {
    // What a provider that answers the first name with a loopback address
    // produces: the connection is refused before anything is sent.
    ExtractorHttp.getOverride = (uri, _) async {
      if (uri.host == 'snap-insta.to') {
        throw http.ClientException('connection refused', uri);
      }
      return _landing();
    };
    Object? sent;
    ExtractorHttp.postOverride = (uri, _, body) async {
      sent = body;
      return _found('<a>${uri.host}</a>');
    };

    final html = await const SnapInstaFallbackClient().search(_reel);

    expect(html, '<a>x2download.com</a>');
    expect(sent, containsPair('q', _reel));
    expect(sent, containsPair('web', 'x2download.com'));
  });

  test('asks the second when the first has nothing', () async {
    ExtractorHttp.getOverride = (_, _) async => _landing();
    ExtractorHttp.postOverride = (uri, _, _) async =>
        uri.host == 'snap-insta.to'
        ? http.Response(jsonEncode({'status': 'error'}), 200)
        : _found('<a>second</a>');

    expect(
      await const SnapInstaFallbackClient().search(_reel),
      '<a>second</a>',
    );
  });

  test('fails as unreachable only when neither could be asked', () async {
    ExtractorHttp.getOverride = (uri, _) async =>
        throw http.ClientException('connection refused', uri);
    ExtractorHttp.postOverride = (_, _, _) async => http.Response('', 500);

    await expectLater(
      const SnapInstaFallbackClient().search(_reel),
      throwsA(anything),
    );
  });
}
