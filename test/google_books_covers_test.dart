import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/google_books_covers_api.dart';
import 'package:sharemarium/models/book.dart';

const sample = Book(
  id: '9784488402327',
  isbn: '9784488402327',
  title: '亜愛一郎の狼狽',
  author: '泡坂妻夫',
  publisher: '東京創元社',
  pubDate: '2026.10',
  coverUrl: '',
);

Map<String, dynamic> cover({
  String thumbnail = 'https://books.google.com/books?id=actual&img=1',
  String attribution = 'https://books.google.com/books?id=actual&source=gbs_ViewAPI',
}) => {'coverUrl': thumbnail, 'creditUrl': attribution};

void main() {
  test('exact ISBN cover enrichment retains a mandatory Google Books link', () {
    final book = GoogleBooksCoversApi.enrichRecord(sample, cover());
    expect(book.id, sample.id);
    expect(book.isbn, sample.isbn);
    expect(book.coverUrl, 'https://books.google.com/books?id=actual&img=1');
    expect(book.coverSource, 'google_books');
    expect(book.coverAttributionUrl, contains('books.google.com'));
  });

  test('openBD and existing licensed cover always take precedence', () {
    final existing = sample.copyWith(
      coverUrl: 'https://publisher.example/book.jpg',
      coverSource: 'openbd',
    );
    final book = GoogleBooksCoversApi.enrichRecord(existing, cover());
    expect(book.coverUrl, existing.coverUrl);
    expect(book.coverSource, 'openbd');
  });

  test('rejects unrelated hosts, http URLs and missing attribution', () {
    for (final metadata in [
      cover(thumbnail: 'https://evil.example/other.jpg'),
      cover(thumbnail: 'http://books.google.com/books?id=actual&img=1'),
      cover(attribution: 'https://evil.example/redirect'),
      cover(attribution: ''),
      cover(thumbnail: 'https://user:pass@books.google.com/cover.jpg'),
    ]) {
      final book = GoogleBooksCoversApi.enrichRecord(sample, metadata);
      expect(book.coverUrl, isEmpty);
      expect(book.coverSource, isEmpty);
    }
  });
}
