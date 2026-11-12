import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/repositories/book_repository.dart';

Book sample(int id, {bool restricted = false, String? title}) => Book(
  id: 'book-$id',
  isbn: (9780000000000 + id).toString(),
  title: title ?? 'Book $id',
  author: 'Writer',
  publisher: 'Publisher',
  pubDate: '2026-11-01',
  coverUrl: '',
  adultContentFlag: restricted,
  ageRatingSource: restricted ? 'openbd' : 'unknown',
  catalogSource: 'rakuten',
);

void main() {

  test('publisher zero is replaced by spare title/author books up to ten', () async {
    final pages = <int>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      rakutenKeywordPageFetcher: (query, upstreamPage, count, fields) async {
        pages.add(upstreamPage);
        expect(count, 10);
        expect(fields, ['author', 'title', 'publisherName']);
        return RakutenKeywordSearchBatch(
          books: [
            ...List.generate(8, (i) => sample(i + 1, title: '芥川 Author $i')),
            ...List.generate(5, (i) => sample(i + 20, title: '芥川 Title $i')),
          ],
          hasMore: false,
        );
      },
    );

    final first = await repo.searchBooksPage('芥川', page: 1, count: 10);
    expect(first.books.length, 10);
    expect(first.hasMore, isTrue, reason: 'Three unused candidates are buffered');

    final second = await repo.searchBooksPage('芥川', page: 2, count: 10);
    expect(second.books.length, 3);
    expect(second.hasMore, isFalse);
    expect(pages, [1], reason: 'Already-fetched spare candidates must not be lost');
    expect([...first.books, ...second.books].map((b) => b.id).toSet().length, 13);
  });

  test('short raw result windows still allow later upstream pages', () async {
    final pages = <int>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      rakutenKeywordPageFetcher: (query, upstreamPage, count, fields) async {
        pages.add(upstreamPage);
        if (upstreamPage == 1) {
          return RakutenKeywordSearchBatch(
            books: List.generate(7, (i) => sample(i + 1)),
            hasMore: true,
          );
        }
        return RakutenKeywordSearchBatch(
          books: List.generate(8, (i) => sample(i + 8)),
          hasMore: false,
        );
      },
    );
    final first = await repo.searchBooksPage('芥川', page: 1, count: 10);
    expect(first.books.length, 10);
    expect(first.hasMore, isTrue);
    final second = await repo.searchBooksPage('芥川', page: 2, count: 10);
    expect(second.books.length, 5);
    expect(second.hasMore, isFalse);
    expect(pages, [1, 2]);
  });


  test('staging shows 27 fetched books in three cached nine-card pages', () async {
    final calls = <String>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      stagingRakutenGenreFetcher: (genre, upstreamPage, count) async {
        calls.add('$genre:$upstreamPage:$count');
        return List.generate(27, (i) => sample((upstreamPage - 1) * 27 + i));
      },
    );
    final pages = <List<Book>>[];
    for (var page = 1; page <= 4; page++) {
      final books = await repo.fetchBooksByGenre('新着', page: page);
      expect(books.length, 9);
      pages.add(books);
    }
    expect(calls, ['新着:1:27', '新着:2:27']);
    final seen = pages.expand((books) => books.map((book) => book.id)).toList();
    expect(seen.toSet().length, 36);
    expect(await repo.fetchBooksByGenre('新着', page: 1), pages.first);
    expect(calls.length, 2, reason: 'going back never refetches from Rakuten');
    expect(repo.hasMoreHomeBooks('新着'), true);
  });

  test('和書 uses normal Japanese BooksBook genre rather than a 和書 keyword', () async {
    final genres = <String>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      stagingRakutenGenreFetcher: (genre, upstreamPage, count) async {
        genres.add(genre);
        return List.generate(12, (i) => sample(i + 1));
      },
    );
    final japanese1 = await repo.fetchBooksByGenre('和書', page: 1);
    final japanese2 = await repo.fetchBooksByGenre('和書', page: 2);
    expect(japanese1.length, 9);
    expect(japanese2.length, 3);
    expect(repo.hasMoreHomeBooks('和書'), false);
    expect(genres, ['']);
    repo.resetHomeBooks('和書');
    expect((await repo.fetchBooksByGenre('和書')).length, 9);
    expect(genres, ['', ''], reason: 'manual retry begins a new request');
    expect((await repo.fetchBooksByGenre('English')).length, 9);
    expect(genres.last, 'English');
  });

  test('adult-content filtering remains enabled and subsequent windows fill gaps', () async {
    final requested = <int>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      stagingRakutenGenreFetcher: (_, page, count) async {
        requested.add(page);
        return List.generate(
          27, (i) => sample((page - 1) * 27 + i, restricted: i < 5),
        );
      },
    );
    final first = await repo.fetchBooksByGenre('English', page: 1);
    final second = await repo.fetchBooksByGenre('English', page: 2);
    final third = await repo.fetchBooksByGenre('English', page: 3);
    expect(first.length, 9);
    expect(second.length, 9);
    expect(third.length, 9);
    expect([...first, ...second, ...third].every(
      (book) => !book.adultContentFlag,
    ), true);
    expect(requested, [1, 2], reason: 'second 27-book batch fills filtered gaps');
  });

  test('staging search uses Rakuten backend without affecting existing NDL tests', () async {
    final requests = <String>[];
    final repo = BookRepository(
      stagingRakuten: true,
      rakutenBookEnricher: (books) async => books,
      stagingRakutenKeywordFetcher: (query, page, count) async {
        requests.add('$query:$page:$count');
        return [sample(1, title: 'Japan Story'), sample(2, restricted: true)];
      },
    );
    final found = await repo.searchBooksPage('Japan', page: 1, count: 2);
    expect(requests, ['Japan:1:2']);
    expect(found.books.length, 1);
    expect(found.books.single.title, 'Japan Story');
    expect(found.hasMore, true);
  });

  test('Rakuten results receive approved openBD cover enrichment', () async {
    final repo = BookRepository(
      stagingRakuten: true,
      stagingRakutenKeywordFetcher: (_, __, ___) async => [sample(1)],
      rakutenBookEnricher: (books) async => books.map((book) => book.copyWith(
        coverUrl: 'https://cover.openbd.jp/${book.isbn}.jpg',
        coverSource: 'openbd',
      )).toList(),
    );
    final found = await repo.searchBooksPage('Book 1');
    expect(found.books.single.coverSource, 'openbd');
    expect(found.books.single.coverUrl, contains('cover.openbd.jp'));
  });
}
