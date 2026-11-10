import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/gallery_notice_text.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/models/gallery_notice.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('every notice renders non-empty text in both locales', () {
    for (final notice in GalleryNotice.values) {
      for (final l10n in [en, vi]) {
        final text = describeGalleryNotice(notice, l10n);
        expect(text, isNotEmpty, reason: '$notice produced empty text');
        // A missed switch arm would leak the enum name to the user.
        expect(text, isNot(contains('GalleryNotice')), reason: '$notice');
      }
    }
  });

  test('the notices read differently', () {
    // They report different situations and only one of them is the reader's
    // to fix, so the same sentence for two of them would be a bug.
    final texts = {
      for (final notice in GalleryNotice.values)
        describeGalleryNotice(notice, en),
    };
    expect(texts, hasLength(GalleryNotice.values.length));
  });

  test('a partly read post does not claim to hold only its cover', () {
    final text = describeGalleryNotice(GalleryNotice.somePhotosMissing, en);
    expect(text, isNot(contains('cover')));
    expect(text, contains('more'));
  });

  test('translations actually differ between locales', () {
    for (final notice in GalleryNotice.values) {
      expect(
        describeGalleryNotice(notice, en),
        isNot(describeGalleryNotice(notice, vi)),
        reason: '$notice was left untranslated',
      );
    }
  });
}
