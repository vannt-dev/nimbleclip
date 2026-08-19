import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/json_scanner.dart';
import 'package:nimble_clip/core/utils/text_unescape.dart';

void main() {
  group('decodeJsonEscapes', () {
    test('unescapes slashes without eating other escapes', () {
      expect(
        decodeJsonEscapes(r'https:\/\/video.xx.fbcdn.net\/v\/t42.mp4'),
        'https://video.xx.fbcdn.net/v/t42.mp4',
      );
    });

    test('decodes unicode escapes instead of dropping the backslash', () {
      // Regression: a blanket backslash strip turned \u00e9 into "u00e9".
      expect(decodeJsonEscapes(r'caf\u00e9'), 'café');
      expect(decodeJsonEscapes(r'Ti\u1ebfng Vi\u1ec7t'), 'Tiếng Việt');
      expect(decodeJsonEscapes(r'a\u0026b'), 'a&b');
      expect(decodeJsonEscapes(r'\u003Cb\u003E'), '<b>');
    });

    test('handles quotes, newlines and literal backslashes', () {
      expect(decodeJsonEscapes(r'say \"hi\"'), 'say "hi"');
      expect(decodeJsonEscapes(r'line1\nline2'), 'line1\nline2');
      expect(decodeJsonEscapes(r'C:\\temp'), r'C:\temp');
    });

    test('leaves plain text untouched', () {
      expect(decodeJsonEscapes('no escapes here'), 'no escapes here');
      expect(decodeJsonEscapes(''), '');
    });

    test('tolerates a truncated escape at the end', () {
      expect(decodeJsonEscapes(r'trailing\'), r'trailing\');
      expect(decodeJsonEscapes(r'bad\uZZ'), 'baduZZ');
    });
  });

  group('decodeHtmlEntities', () {
    test('decodes the common entities', () {
      expect(decodeHtmlEntities('Tom &amp; Jerry'), 'Tom & Jerry');
      expect(decodeHtmlEntities('&quot;quoted&quot;'), '"quoted"');
      expect(decodeHtmlEntities('it&#039;s'), "it's");
      expect(decodeHtmlEntities('&lt;b&gt;'), '<b>');
    });

    test('resolves &amp; last so &amp;quot; does not become a quote', () {
      expect(decodeHtmlEntities('&amp;quot;'), '&quot;');
    });
  });

  group('extractBalancedJson', () {
    test('returns the whole object, not the first closing brace', () {
      const source = 'var x = {"a":{"b":1},"c":2}; more junk';
      final blob = extractBalancedJson(source, 0);
      expect(blob, '{"a":{"b":1},"c":2}');
      expect(jsonDecode(blob!)['c'], 2);
    });

    test('does not stop at a brace inside a string literal', () {
      // Regression: `({.+?});` truncated ytInitialPlayerResponse at the first
      // "};" that appeared inside a string value.
      const source = 'ytInitialPlayerResponse = {"t":"a};b","n":{"x":1}};';
      final blob = extractJsonAfterMarker(source, 'ytInitialPlayerResponse');
      expect(blob, '{"t":"a};b","n":{"x":1}}');

      final decoded = jsonDecode(blob!) as Map<String, dynamic>;
      expect(decoded['t'], 'a};b');
      expect((decoded['n'] as Map)['x'], 1);
    });

    test('handles escaped quotes inside strings', () {
      const source = r'{"quote":"he said \"hi\" }","after":true}';
      final blob = extractBalancedJson(source, 0);
      expect(jsonDecode(blob!)['after'], true);
    });

    test('returns null when the object never closes', () {
      expect(extractBalancedJson('{"a":1', 0), isNull);
      expect(extractBalancedJson('no braces', 0), isNull);
    });

    test('returns null when the marker is absent', () {
      expect(extractJsonAfterMarker('nothing here', 'missingMarker'), isNull);
    });
  });
}
