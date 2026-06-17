import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/utils/text_utils.dart';

void main() {
  group('containsJapanese', () {
    test('returns true for hiragana', () {
      expect(containsJapanese('こんにちは'), isTrue);
    });

    test('returns false for English', () {
      expect(containsJapanese('Hello world'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsJapanese(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsJapanese(null), isFalse);
    });
  });

  group('containsKorean', () {
    test('returns true for Hangul syllables', () {
      expect(containsKorean('안녕하세요'), isTrue);
    });

    test('returns false for Japanese', () {
      expect(containsKorean('こんにちは'), isFalse);
    });

    test('returns false for null', () {
      expect(containsKorean(null), isFalse);
    });
  });

  group('containsChinese', () {
    test('returns true for Simplified Chinese', () {
      expect(containsChinese('你好世界'), isTrue);
    });

    test('returns false for Korean', () {
      expect(containsChinese('안녕하세요'), isFalse);
    });
  });

  group('containsCyrillic', () {
    test('returns true for Russian', () {
      expect(containsCyrillic('Привет мир'), isTrue);
    });

    test('returns false for null', () {
      expect(containsCyrillic(null), isFalse);
    });
  });

  group('containsArabic', () {
    test('returns true for Arabic text', () {
      expect(containsArabic('مرحبا بالعالم'), isTrue);
    });

    test('returns false for null', () {
      expect(containsArabic(null), isFalse);
    });
  });

  group('containsHebrew', () {
    test('returns true for Hebrew text', () {
      expect(containsHebrew('שלום עולם'), isTrue);
    });

    test('returns false for null', () {
      expect(containsHebrew(null), isFalse);
    });
  });

  group('containsRomanizableText', () {
    test('returns true for Japanese', () {
      expect(containsRomanizableText('こんにちは'), isTrue);
    });

    test('returns false for English', () {
      expect(containsRomanizableText('Hello world'), isFalse);
    });

    test('returns false for null', () {
      expect(containsRomanizableText(null), isFalse);
    });
  });
}
