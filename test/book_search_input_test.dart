import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/controllers/book_list_controller.dart';

void main() {
  test('日本語IMEの変換中は書籍検索を開始しない', () {
    const composing = TextEditingValue(
      text: 'あくたがわ',
      composing: TextRange(start: 0, end: 5),
    );

    expect(BookListController.isComposingSearchInput(composing), isTrue);
  });

  test('日本語IMEで確定した文字列は書籍検索できる', () {
    const committed = TextEditingValue(
      text: '芥川',
      composing: TextRange.empty,
    );

    expect(BookListController.isComposingSearchInput(committed), isFalse);
  });

  test('貼り付けや英字入力は書籍検索できる', () {
    const pasted = TextEditingValue(text: 'Michael');

    expect(BookListController.isComposingSearchInput(pasted), isFalse);
  });
}
