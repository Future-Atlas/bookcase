import 'package:flutter/services.dart';

const reservedPublicUserIds = <String>{
  'admin',
  'administrator',
  'support',
  'sharemarium',
  'system',
  'official',
};

String normalizePublicUserId(String value) => value.toLowerCase();

String? validatePublicUserId(String? value) {
  final id = value ?? '';
  if (id.isEmpty) return 'ユーザーIDを入力してください。';
  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id)) {
    return 'ユーザーIDに使用できる文字は、半角英字・数字・アンダースコア ( _ ) のみです。';
  }
  if (id.length < 3 || id.length > 20) {
    return 'ユーザーIDは3〜20文字で入力してください。';
  }
  if (reservedPublicUserIds.contains(normalizePublicUserId(id))) {
    return 'このユーザーIDは使用できません。';
  }
  return null;
}

/// Converts only confirmed ASCII letters to lowercase.
///
/// Text under IME composition is left untouched so mobile Japanese keyboards
/// do not lose or hide unconfirmed characters. Invalid characters remain
/// visible and are reported by validation instead of being silently removed.
class LowerCasePublicUserIdFormatter extends TextInputFormatter {
  const LowerCasePublicUserIdFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
      return newValue;
    }
    final lowercased = newValue.text.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (match) => match.group(0)!.toLowerCase(),
    );
    return newValue.copyWith(text: lowercased);
  }
}
