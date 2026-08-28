import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/extractors/registry.dart';

const _runLive = bool.fromEnvironment('RUN_LIVE_EXTRACTOR_TESTS');
const _instagramImageUrl = String.fromEnvironment('INSTAGRAM_IMAGE_URL');
const _instagramVideoUrl = String.fromEnvironment('INSTAGRAM_VIDEO_URL');

void main() {
  final registry = ExtractorRegistry();

  final cases = <String, ({String url, int minimumMedia})>{
    if (_instagramImageUrl.isNotEmpty)
      'Instagram carousel': (url: _instagramImageUrl, minimumMedia: 2),
    if (_instagramVideoUrl.isNotEmpty)
      'Instagram video': (url: _instagramVideoUrl, minimumMedia: 1),
    'Facebook gallery': (
      url: 'https://www.facebook.com/cebuanafinance/posts/662287040177856/',
      minimumMedia: 2,
    ),
    'X gallery': (
      url: 'https://x.com/SpaceX/status/2000459900460347480',
      minimumMedia: 2,
    ),
    'X video': (
      url: 'https://x.com/SpaceX/status/1897790210219311202',
      minimumMedia: 1,
    ),
    'TikTok slideshow': (
      url: 'https://www.tiktok.com/@qq.mm.pp/photo/7479037796326362385',
      minimumMedia: 2,
    ),
    'TikTok video': (
      url: 'https://www.tiktok.com/@sydneygurung/video/7663135895184362770',
      minimumMedia: 1,
    ),
  };

  for (final entry in cases.entries) {
    test(
      entry.key,
      () async {
        final metadata = await registry.extract(entry.value.url);
        expect(
          metadata.qualities.length,
          greaterThanOrEqualTo(entry.value.minimumMedia),
        );
        expect(
          metadata.qualities.every(
            (option) => Uri.tryParse(option.downloadUrl)?.hasScheme == true,
          ),
          isTrue,
        );
      },
      skip: !_runLive
          ? 'Run tool/check_live_extractors.ps1 to test live services.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
