import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/ndl_api.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/repositories/book_repository.dart';

Book candidate(int id, {
  String language = 'jpn',
  bool restricted = false,
  String title = '',
}) {
  final isbn = (1000000000 + id).toString();
  return Book(
    id: isbn,
    isbn: isbn,
    title: title.isEmpty ? '一般書籍' + id.toString() : title,
    author: '著者',
    publisher: '出版社',
    pubDate: '2026-10-' + (id % 28 + 1).toString().padLeft(2, '0'),
    coverUrl: '',
    languageCode: language,
    adultContentFlag: restricted,
    ageRatingSource: restricted ? 'openbd' : 'unknown',
  );
}

void main() {
  test('new-arrival pages fill 9 while preserving unseen ISBNs and skips', () async {
    final requested = <int>[];
    Future<NdlSearchBatch> fetch({
      required String provider, String? any, String? from,
      required int start, required int count,
    }) async {
      expect(provider, NdlApi.inProcess);
      expect(from, isNotEmpty);
      expect(count, 27);
      requested.add(start);
      if (start == 1) {
        return NdlSearchBatch(
          books: List.generate(5, (i) =>
              candidate(i + 1, restricted: i == 1)),
          rawCount: 27, hasMore: true,
        );
      }
      if (start == 28) {
        return NdlSearchBatch(
          books: [
            candidate(5),
            ...List.generate(12, (i) => candidate(i + 6)),
          ],
          rawCount: 27, hasMore: true,
        );
      }
      if (start == 55) {
        return NdlSearchBatch(
          books: List.generate(15, (i) => candidate(i + 18)),
          rawCount: 27, hasMore: true,
        );
      }
      return const NdlSearchBatch(books: [], rawCount: 0, hasMore: false);
    }
    final repo = BookRepository(homeFetcher: fetch);
    final first = await repo.fetchBooksByGenre('新着');
    expect(first.length, 9);
    expect(first.any((book) => book.adultContentFlag), false);
    expect(first.any((book) => book.id == candidate(1).id), true);
    final second = await repo.fetchBooksByGenre('新着', page: 2);
    expect(second.length, 9);
    final firstIds = first.map((book) => book.id).toSet();
    final secondIds = second.map((book) => book.id).toSet();
    expect(firstIds.intersection(secondIds), isEmpty);
    expect(firstIds.length + secondIds.length, 18);
    expect(requested, [1, 28, 55]);
    final cached = await repo.fetchBooksByGenre('新着', page: 1);
    expect(cached.map((book) => book.id), first.map((book) => book.id));
    expect(requested, [1, 28, 55], reason: 'cached page must not refetch');
    expect(repo.hasMoreHomeBooks('新着'), true);
  });

  test('new arrivals fall back after sparse in-process metadata', () async {
    final providers = <String>[];
    Future<NdlSearchBatch> fetch({
      required String provider, String? any, String? from,
      required int start, required int count,
    }) async {
      providers.add(provider + ':' + start.toString());
      if (provider == NdlApi.inProcess) {
        return const NdlSearchBatch(books: [], rawCount: 27, hasMore: true);
      }
      return NdlSearchBatch(
        books: List.generate(14, (i) => candidate(40 + i)),
        rawCount: 27, hasMore: true,
      );
    }
    final repo = BookRepository(homeFetcher: fetch);
    final first = await repo.fetchBooksByGenre('新着');
    expect(first.length, 9);
    expect(providers, [
      NdlApi.inProcess + ':1',
      NdlApi.inProcess + ':28',
      NdlApi.national + ':1',
    ]);
  });

  test('foreign feed scans further and excludes Japanese-only books', () async {
    final providers = <String>[];
    Future<NdlSearchBatch> fetch({
      required String provider, String? any, String? from,
      required int start, required int count,
    }) async {
      providers.add(provider + ':' + start.toString() + ':' + (any ?? ''));
      if (provider == NdlApi.foreignBibliography && start == 1) {
        return NdlSearchBatch(
          books: [
            candidate(70, language: 'eng'),
            candidate(71, language: 'spa'),
            candidate(72, language: 'jpn'),
            candidate(73, language: ''),
            candidate(74, language: 'deu', restricted: true),
            candidate(75, language: 'eng'),
          ],
          rawCount: 27, hasMore: true,
        );
      }
      if (provider == NdlApi.foreignBibliography) {
        return NdlSearchBatch(
          books: List.generate(12, (i) =>
              candidate(100 + i, language: 'ja')),
          rawCount: 27, hasMore: true,
        );
      }
      expect(provider, NdlApi.holdings);
      expect(any, 'English');
      return NdlSearchBatch(
        books: List.generate(15, (i) =>
            candidate(170 + i, language: 'eng')),
        rawCount: 27, hasMore: true,
      );
    }
    final repo = BookRepository(homeFetcher: fetch);
    final western = await repo.fetchBooksByGenre('English');
    expect(western.length, 9);
    expect(western.every(NdlApi.isForeignLanguage), true);
    expect(western.any((book) => book.id == candidate(71).id), true);
    expect(western.any((book) => book.id == candidate(72).id), false);
    expect(western.any((book) => book.id == candidate(74).id), false);
    expect(providers.first, NdlApi.foreignBibliography + ':1:');
    expect(providers, contains(NdlApi.holdings + ':1:English'));
    final next = await repo.fetchBooksByGenre('English', page: 2);
    expect(next.length, 9);
    expect(western.map((book) => book.id).toSet()
      .intersection(next.map((book) => book.id).toSet()), isEmpty);
  });

  test('no placeholder books are manufactured when NDL has no matches', () async {
    Future<NdlSearchBatch> fetch({
      required String provider, String? any, String? from,
      required int start, required int count,
    }) async => const NdlSearchBatch(
      books: [], rawCount: 0, hasMore: false,
    );
    final repo = BookRepository(homeFetcher: fetch);
    expect(await repo.fetchBooksByGenre('新着'), isEmpty);
    expect(repo.hasMoreHomeBooks('新着'), isFalse);
    expect(await repo.fetchBooksByGenre('洋書'), isEmpty);
    expect(repo.hasMoreHomeBooks('洋書'), isFalse);
  });

  test('foreign language policy checks language, not title words', () {
    expect(NdlApi.isForeignLanguage(candidate(1, language: 'eng')), true);
    expect(NdlApi.isForeignLanguage(candidate(2, language: 'spa')), true);
    expect(NdlApi.isForeignLanguage(candidate(3, language: 'jpn eng')), true);
    expect(NdlApi.isForeignLanguage(candidate(4, language: 'jpn')), false);
    expect(NdlApi.isForeignLanguage(candidate(5, language: 'und')), false);
    expect(NdlApi.isForeignLanguage(candidate(
      6, language: '', title: 'An English Language Book',
    )), false);
  });
}
