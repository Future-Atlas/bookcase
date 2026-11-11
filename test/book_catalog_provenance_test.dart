import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';

void main() {
  test('Rakuten data has explicit source and transient capture time', () {
    final book = Book.fromRakutenJson({
      'isbn': '9784101010014',
      'title': 'テスト本',
      'author': '著者',
      'itemPrice': 500,
    });
    expect(book.catalogSource, 'rakuten');
    expect(book.catalogFetchedAt, isNotNull);
    final changed = book.copyWith(title: '編集した表示名');
    expect(changed.catalogSource, 'rakuten');
    expect(changed.catalogFetchedAt, book.catalogFetchedAt);
  });

  test('NDL data is never mislabelled as Rakuten metadata', () {
    final book = Book.fromNdlJson({
      'isbn': '9784101010014',
      'title': 'NDL本',
      'creator': '著者',
    });
    expect(book.catalogSource, 'ndl');
    expect(book.catalogFetchedAt, isNotNull);
    expect(book.rakutenAffiliateUrl, isEmpty);
  });

  test('curated and legacy identity is unverified until provenance is confirmed', () {
    const book = Book(
      id: '9784101010014',
      isbn: '9784101010014',
      title: '利用者が選んだ本',
      author: '',
      publisher: '',
      pubDate: '',
      coverUrl: '',
    );
    expect(book.catalogSource, 'unverified');
    expect(book.catalogFetchedAt, isNull);
  });
}
