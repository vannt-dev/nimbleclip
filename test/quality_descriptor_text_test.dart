import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/l10n/quality_descriptor_text.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';

/// One of every variant, so a new descriptor without a case here is noticed.
const _all = <QualityDescriptor>[
  ImageIndex(3),
  VideoIndex(2),
  Hd720(),
  Sd480(),
  OriginalVideo(),
  OriginalMp4(),
  OriginalAudio(),
  EmbeddedVideo(),
  AudioMp3('Some song'),
  AudioM4a(128),
  VideoWithAudio('720p'),
  WatermarkedVideo('720p', watermarked: false),
  WatermarkedVideo('720p', watermarked: true),
  VideoBitrate('480p', 832),
  LiteralLabel('carried over'),
];

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('every descriptor renders non-empty text in both locales', () {
    for (final descriptor in _all) {
      for (final l10n in [en, vi]) {
        final text = describeQuality(descriptor, l10n);
        expect(text, isNotEmpty, reason: '$descriptor produced empty text');
        expect(
          text,
          isNot(contains('Instance of')),
          reason: '$descriptor leaked an object',
        );
      }
    }
  });

  test('substitutions reach the rendered text', () {
    expect(describeQuality(const ImageIndex(7), en), contains('7'));
    expect(describeQuality(const AudioM4a(192), en), contains('192'));
    expect(
      describeQuality(const AudioMp3('Night Drive'), en),
      contains('Night Drive'),
    );
    expect(
      describeQuality(const VideoWithAudio('1080p'), en),
      contains('1080p'),
    );
  });

  test('the two watermark states read differently', () {
    const quality = '720p';
    final without = describeQuality(
      const WatermarkedVideo(quality, watermarked: false),
      en,
    );
    final with_ = describeQuality(
      const WatermarkedVideo(quality, watermarked: true),
      en,
    );
    expect(without, isNot(with_));
    expect(without, contains(en.noWatermark));
    expect(with_, contains(en.withWatermark));
  });

  test('the bitrate variant carries both parts', () {
    final text = describeQuality(const VideoBitrate('480p', 832), en);
    expect(text, contains('480p'));
    expect(text, contains('832'));
  });

  test('a carried-over label renders verbatim', () {
    // It came from a payload written before descriptors existed, so there is
    // nothing to translate — the stored text is all there is.
    expect(describeQuality(const LiteralLabel('Ảnh 2'), en), 'Ảnh 2');
  });

  test('translations actually differ between locales', () {
    expect(
      describeQuality(const Hd720(), en),
      isNot(describeQuality(const Hd720(), vi)),
    );
  });
}
