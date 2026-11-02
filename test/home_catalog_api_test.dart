import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/home_catalog_api.dart';
import 'package:sharemarium/api/ndl_api.dart';

void main() {
  test('home API only contacts a same-origin, bounded language page', () {
    final japanese = HomeCatalogApi.searchUri(
      language: 'jpn', topic: '日本', start: 1,
    );
    expect(japanese.path, '/api/home-catalog');
    expect(japanese.queryParameters['lang'], 'jpn');
    expect(japanese.queryParameters['topic'], '日本');
    expect(japanese.queryParameters['page'], '1');
    final next = HomeCatalogApi.searchUri(
      language: 'eng', topic: 'Japan', start: 61,
    );
    expect(next.queryParameters['page'], '2');
  });

  test('home decoder requires exact edition language, ISBN and distinct id', () {
    final batch = HomeCatalogApi.parseDecoded({
      'catalogSource': 'openlibrary',
      'rawCount': 60,
      'hasMore': true,
      'books': [
        {
          'isbn': '9780140328721', 'languageCode': 'eng',
          'title': 'English Edition', 'author': 'Author',
        },
        {
          'isbn': '9780140328721', 'languageCode': 'eng',
          'title': 'Duplicate',
        },
        {
          'isbn': '9780140328720', 'languageCode': 'eng',
          'title': 'Invalid Checksum',
        },
        {
          'isbn': '9780140328721', 'languageCode': 'jpn',
          'title': 'Wrong Language',
        },
        {
          'isbn': '9780140328721', 'languageCode': 'jpn eng',
          'title': 'Bilingual',
        },
        {
          'isbn': '', 'languageCode': 'eng',
          'title': 'No ISBN',
        },
      ],
    }, language: 'eng', genre: 'English');
    expect(batch.books.length, 1);
    expect(batch.books.single.isbn, '9780140328721');
    expect(batch.books.single.languageCode, 'eng');
    expect(NdlApi.isEnglishLanguage(batch.books.single), isTrue);
    expect(batch.books.single.catalogSource, 'openlibrary');
    expect(batch.books.single.coverUrl, isEmpty,
        reason: 'Do not use Open Library images or unlicensed fallback');
    expect(batch.rawCount, 60);
    expect(batch.hasMore, isTrue);
  });

  test('Japanese source keeps exact Japanese language and rejects English', () {
    final batch = HomeCatalogApi.parseDecoded({
      'catalogSource': 'openlibrary', 'rawCount': 2, 'hasMore': false,
      'books': [
        {'isbn': '9780140328721', 'languageCode': 'jpn', 'title': '日本語版'},
        {'isbn': '9780140328720', 'languageCode': 'jpn', 'title': '不正ISBN'},
        {'isbn': '9780140328721', 'languageCode': 'eng', 'title': 'English'},
      ],
    }, language: 'jpn', genre: '和書');
    expect(batch.books.length, 1);
    expect(NdlApi.isJapaneseLanguage(batch.books.single), isTrue);
    expect(batch.hasMore, isFalse);
  });

  test('invalid or unexpected JSON never becomes an empty completed catalog', () {
    final batch = HomeCatalogApi.parseDecoded({
      'books': <Object>[], 'rawCount': 0, 'hasMore': false,
    }, language: 'jpn');
    expect(batch.books, isEmpty);
    expect(batch.temporarilyUnavailable, isTrue);
  });
}
