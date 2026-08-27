import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/extraction_failure_text.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('every failure kind renders non-empty text in both locales', () {
    for (final kind in ExtractionFailureKind.values) {
      final failure = ExtractionFailure(kind, detail: 'boom');
      for (final l10n in [en, vi]) {
        final text = describeExtractionFailure(failure, l10n);
        expect(text, isNotEmpty, reason: '$kind produced empty text');
        // A missed switch arm would leak the enum name to the user.
        expect(text, isNot(contains('ExtractionFailureKind')), reason: '$kind');
      }
    }
  });

  test('kinds without a detail ignore one that is supplied', () {
    const withDetail = ExtractionFailure(
      ExtractionFailureKind.xNoVideo,
      detail: 'ignored',
    );
    const without = ExtractionFailure(ExtractionFailureKind.xNoVideo);
    expect(
      describeExtractionFailure(withDetail, en),
      describeExtractionFailure(without, en),
    );
  });

  test('detail is substituted into the kinds that take one', () {
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: 'socket closed',
        ),
        en,
      ),
      contains('socket closed'),
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.tiktokServiceStatus,
          detail: '503',
        ),
        en,
      ),
      contains('503'),
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.youtubePlaybackRejected,
          detail: 'AGE_VERIFICATION_REQUIRED',
        ),
        en,
      ),
      contains('AGE_VERIFICATION_REQUIRED'),
    );
  });

  test('a TikTok server message is passed through, prefixed', () {
    // Preserves today's behaviour: when TikTok supplies its own `msg`, that
    // text is shown verbatim rather than the generic localized sentence.
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.tiktokInvalidData,
          detail: 'video removed',
        ),
        en,
      ),
      'TikTok: video removed',
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(ExtractionFailureKind.tiktokInvalidData),
        en,
      ),
      en.tiktokInvalidData,
    );
  });

  test('translations actually differ between locales', () {
    const failure = ExtractionFailure(ExtractionFailureKind.invalidLink);
    expect(
      describeExtractionFailure(failure, en),
      isNot(describeExtractionFailure(failure, vi)),
    );
  });
}
