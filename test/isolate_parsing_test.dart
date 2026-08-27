import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/extractors/facebook_page_parser.dart';
import 'package:nimble_clip/services/extractors/parse_offloading.dart';

/// Builds a page whose inline JSON is large enough to cross the offload
/// threshold, carrying [photoCount] distinct photo nodes.
String largePage(int photoCount) {
  final photos = [
    for (var index = 0; index < photoCount; index++)
      {
        '__typename': 'Photo',
        'id': '$index',
        'image': {
          'uri':
              'https://scontent.xx.fbcdn.net/v/t39.30808-6/photo_$index.jpg'
              '?stp=dst-jpg&amp;ccb=1-7&amp;oe=66F0A1B2',
          'width': 2048,
          'height': 1536,
        },
      },
  ];
  // Padding so the document is comfortably past the threshold.
  final padding = List.filled(
    (parseOffloadThresholdBytes ~/ 40) + 200,
    '{"noise":"xxxxxxxxxxxxxxxxxxxxxxxxxxxx"}',
  ).join(',');
  return '<html><body>'
      '<script type="application/json">${jsonEncode(photos)}</script>'
      '<script type="application/json">[$padding]</script>'
      '</body></html>';
}

void main() {
  const parser = FacebookPageParser();

  test('a small page is parsed without leaving the current isolate', () async {
    final page =
        '<html><script type="application/json">'
        '${jsonEncode([
          {
            '__typename': 'Photo',
            'image': {'uri': 'https://scontent.xx.fbcdn.net/v/t39.30808-6/one.jpg', 'width': 1080, 'height': 1080},
          },
        ])}'
        '</script></html>';
    expect(page.length, lessThan(parseOffloadThresholdBytes));

    final urls = await parser.photoUrlsAsync(page);
    expect(urls, ['https://scontent.xx.fbcdn.net/v/t39.30808-6/one.jpg']);
  });

  test('a large page produces the same photos as the inline parser', () async {
    final page = largePage(6);
    expect(page.length, greaterThan(parseOffloadThresholdBytes));

    final offloaded = await parser.photoUrlsAsync(page);
    final inline = parser.photoUrls(page);

    expect(offloaded, inline);
    expect(offloaded, hasLength(6));
    expect(
      offloaded.first,
      'https://scontent.xx.fbcdn.net/v/t39.30808-6/photo_0.jpg'
      '?stp=dst-jpg&ccb=1-7&oe=66F0A1B2',
    );
  });
}
