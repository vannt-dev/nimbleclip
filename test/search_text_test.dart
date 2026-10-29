import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/core/utils/search_text.dart';

void main() {
  group('foldForSearch', () {
    test('drops Vietnamese tone marks and vowel marks', () {
      expect(foldForSearch('Tiếng Việt'), 'tieng viet');
      expect(
        foldForSearch('Ước mơ của những đứa trẻ'),
        'uoc mo cua nhung dua tre',
      );
      expect(foldForSearch('Hồ Gươm, Hà Nội'), 'ho guom, ha noi');
    });

    test('turns đ and Đ into d', () {
      expect(foldForSearch('ĐÀ NẴNG'), 'da nang');
      expect(foldForSearch('đường phố'), 'duong pho');
    });

    test('folds text written with combining marks', () {
      // "Việt" as e + combining circumflex + combining dot below.
      expect(foldForSearch('Việt'), 'viet');
    });

    test('folds common Latin accents and case', () {
      expect(foldForSearch('Café Crème BRÛLÉE'), 'cafe creme brulee');
      expect(foldForSearch('Ñandú Über'), 'nandu uber');
    });

    test('collapses runs of white space and trims', () {
      expect(foldForSearch('  live \t  show\n'), 'live show');
    });

    test('leaves plain text, digits and other scripts alone', () {
      expect(foldForSearch('clip 2024 #1'), 'clip 2024 #1');
      expect(foldForSearch('東京 夜景'), '東京 夜景');
    });
  });
}
