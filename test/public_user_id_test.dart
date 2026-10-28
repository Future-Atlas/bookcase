import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/public_user_id.dart';

void main() {
  group('validatePublicUserId', () {
    test('accepts ASCII letters, numbers, and underscore', () {
      expect(validatePublicUserId('Reader_123'), isNull);
      expect(normalizePublicUserId('Reader_123'), 'reader_123');
    });

    test('reports unsupported characters instead of deleting them', () {
      const message = 'ユーザーIDに使用できる文字は、半角英字・数字・アンダースコア ( _ ) のみです。';
      expect(validatePublicUserId('読書好き'), message);
      expect(validatePublicUserId('reader-name'), message);
      expect(validatePublicUserId('reader name'), message);
    });

    test('checks length and reserved IDs separately', () {
      expect(validatePublicUserId('ab'), 'ユーザーIDは3〜20文字で入力してください。');
      expect(validatePublicUserId('Admin'), 'このユーザーIDは使用できません。');
    });
  });

  group('LowerCasePublicUserIdFormatter', () {
    const formatter = LowerCasePublicUserIdFormatter();

    test('lowercases confirmed ASCII letters', () {
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(
        text: 'Reader_1',
        selection: TextSelection.collapsed(offset: 8),
      );
      final formatted = formatter.formatEditUpdate(oldValue, newValue);
      expect(formatted.text, 'reader_1');
      expect(formatted.selection, newValue.selection);
    });

    test('does not alter text while an IME composition is active', () {
      const oldValue = TextEditingValue.empty;
      const composingValue = TextEditingValue(
        text: 'Ｒｅａｄｅｒ',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 0, end: 6),
      );
      final formatted = formatter.formatEditUpdate(oldValue, composingValue);
      expect(formatted, composingValue);
    });
  });
}
