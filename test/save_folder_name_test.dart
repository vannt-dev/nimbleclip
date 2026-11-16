import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/save_folder_name.dart';

void main() {
  group('SaveFolderName.problemWith', () {
    test('accepts a plain name, with spaces, accents and digits', () {
      expect(SaveFolderName.problemWith('Downloads'), isNull);
      expect(SaveFolderName.problemWith('My clips 2026'), isNull);
      expect(SaveFolderName.problemWith('Video tải về'), isNull);
    });

    test('an empty name means the default folders', () {
      expect(SaveFolderName.problemWith(''), isNull);
      expect(SaveFolderName.problemWith('   '), isNull);
      expect(SaveFolderName.normalize('   '), isNull);
    });

    test('refuses characters a folder name cannot hold', () {
      for (final name in [
        'a/b',
        r'a\b',
        'a:b',
        'a*b',
        'a?b',
        'a"b',
        'a<b',
        'a>b',
        'a|b',
      ]) {
        expect(
          SaveFolderName.problemWith(name),
          SaveFolderProblem.invalidCharacters,
          reason: name,
        );
      }
      expect(
        SaveFolderName.problemWith('a\u0007b'),
        SaveFolderProblem.invalidCharacters,
      );
    });

    test(
      'refuses a name that starts with a dot, which would hide the folder',
      () {
        expect(
          SaveFolderName.problemWith('.hidden'),
          SaveFolderProblem.startsWithDot,
        );
        expect(
          SaveFolderName.problemWith('..'),
          SaveFolderProblem.startsWithDot,
        );
      },
    );

    test('refuses a name longer than the limit', () {
      final limit = SaveFolderName.maxLength;
      expect(SaveFolderName.problemWith('a' * limit), isNull);
      expect(
        SaveFolderName.problemWith('a' * (limit + 1)),
        SaveFolderProblem.tooLong,
      );
    });

    test('normalize trims the name it accepts', () {
      expect(SaveFolderName.normalize('  Clips  '), 'Clips');
    });
  });
}
