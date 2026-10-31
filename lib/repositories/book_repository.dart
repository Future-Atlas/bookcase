import 'dart:math';

import '../models/book.dart';
import '../api/ndl_api.dart';
import '../api/openbd_api.dart';
import '../services/content_safety_service.dart';
import '../services/supabase_service.dart';

enum BookSearchField { title, author, publisher }

/// Injectable only so paging/ranking behavior can be tested without network.
typedef NdlFieldFetcher = Future<NdlSearchBatch> Function(
  BookSearchField field, String term, String provider, int start, int count,
);

class BookSearchBatch {
  const BookSearchBatch({required this.books, required this.hasMore});
  final List<Book> books;
  final bool hasMore;
}

extension BookSearchFieldApiName on BookSearchField {
  String get apiName => switch (this) {
    BookSearchField.title => 'title',
    BookSearchField.author => 'author',
    BookSearchField.publisher => 'publisherName',
  };
}

class BookRepository {
  static final Random _homeRandom = Random();

  BookRepository({this.allowAdultContent = false, this.fieldFetcher});

  final bool allowAdultContent;
  final NdlFieldFetcher? fieldFetcher;
  String _activeQuery = '';
  int _nextSearchPage = 1;
  List<_NdlFieldCursor> _cursors = [];
  final Set<String> _searchSeenIds = <String>{};
  Future<List<Book>>? _popularCache;

  static String _normalizeForSearch(String input) =>
      input.toLowerCase().replaceAll(RegExp(r'[^0-9a-zぁ-んァ-ヶ一-龥]+'), '');

  static String _normalizeForExact(String input) =>
      input.trim().toLowerCase().replaceAll(RegExp(r'[\s\u3000・･]+'), '');

  static int _matchQuality(String value, String query, List<String> tokens) {
    if (value == query) return 4;
    if (value.startsWith(query)) return 3;
    if (value.contains(query)) return 2;
    if (tokens.isNotEmpty && tokens.every(value.contains)) return 1;
    return 0;
  }

  static List<BookSearchField> searchFieldPriority(String rawQuery) {
    final query = rawQuery.trim();
    final normalized = _normalizeForSearch(query);
    const titleFirst = <BookSearchField>[
      BookSearchField.title,
      BookSearchField.author,
      BookSearchField.publisher,
    ];
    const authorFirst = <BookSearchField>[
      BookSearchField.author,
      BookSearchField.title,
      BookSearchField.publisher,
    ];
    const publisherFirst = <BookSearchField>[
      BookSearchField.publisher,
      BookSearchField.title,
      BookSearchField.author,
    ];

    if (query.endsWith('社')) return publisherFirst;

    final lowerQuery = query.toLowerCase();
    if (RegExp(r'(co\.|comics)\s*$').hasMatch(lowerQuery)) {
      return publisherFirst;
    }

    final containsLatin = RegExp(r'[a-zA-Z]').hasMatch(query);
    if (containsLatin) {
      if (RegExp(r'[!！?？:：()（）*＊]').hasMatch(query)) {
        return titleFirst;
      }
      if (RegExp(
        r"^[A-Za-z][A-Za-z.'’\-]*[\s\u3000]+[A-Za-z][A-Za-z.'’\-]*$",
      ).hasMatch(query)) {
        return authorFirst;
      }
      return titleFirst;
    }

    if (RegExp(r'[ァ-ヶー]+[・･][ァ-ヶー]+').hasMatch(query)) {
      return authorFirst;
    }

    final containsJapanese = RegExp(r'[ぁ-んァ-ヶ一-龥]').hasMatch(query);
    final containsSpace = RegExp(r'[\s\u3000]').hasMatch(query);
    if (containsJapanese &&
        !containsSpace &&
        normalized.length >= 3 &&
        normalized.length <= 5) {
      return authorFirst;
    }

    return titleFirst;
  }

  static String _fieldValue(Book book, BookSearchField field) =>
      switch (field) {
        BookSearchField.title => book.title,
        BookSearchField.author => book.author,
        BookSearchField.publisher => book.publisher,
      };

  static _RankedBook _rankedBook(Book book, String rawQuery) {
    final query = _normalizeForSearch(rawQuery);
    if (query.isEmpty) {
      return _RankedBook(book: book, priorityIndex: 3, quality: 0);
    }
    final tokens = rawQuery
        .split(RegExp(r'[\s\u3000・･]+'))
        .map(_normalizeForSearch)
        .where((token) => token.isNotEmpty)
        .toList();
    final priorities = searchFieldPriority(rawQuery);
    final qualities = <int>[];
    for (final field in priorities) {
      qualities.add(
        _matchQuality(
          _normalizeForSearch(_fieldValue(book, field)),
          query,
          tokens,
        ),
      );
    }

    // 指定どおり、スペースと中点だけを除いた完全一致は入力分類より常に優先する。
    final exactQuery = _normalizeForExact(rawQuery);
    for (var index = 0; index < qualities.length; index++) {
      if (_normalizeForExact(_fieldValue(book, priorities[index])) ==
          exactQuery) {
        return _RankedBook(
          book: book,
          priorityIndex: index,
          quality: qualities[index],
          isExact: true,
        );
      }
    }
    for (var index = 0; index < qualities.length; index++) {
      if (qualities[index] > 0) {
        return _RankedBook(
          book: book,
          priorityIndex: index,
          quality: qualities[index],
        );
      }
    }
    return _RankedBook(book: book, priorityIndex: 3, quality: 0);
  }

  static List<Book> rankSearchResults(Iterable<Book> source, String query) {
    final ranked = source.map((book) => _rankedBook(book, query)).toList();

    int compareMatches(_RankedBook a, _RankedBook b) {
      final quality = b.quality.compareTo(a.quality);
      if (quality != 0) return quality;
      final reviews = b.book.reviewCount.compareTo(a.book.reviewCount);
      if (reviews != 0) return reviews;
      final rating = b.book.ratingAvg.compareTo(a.book.ratingAvg);
      if (rating != 0) return rating;
      return a.book.title.compareTo(b.book.title);
    }

    final exact = ranked.where((item) => item.isExact).toList()
      ..sort((a, b) {
        final priority = a.priorityIndex.compareTo(b.priorityIndex);
        return priority != 0 ? priority : compareMatches(a, b);
      });
    final buckets = List.generate(4, (index) {
      final values = ranked
          .where((item) => !item.isExact && item.priorityIndex == index)
          .toList();
      values.sort(compareMatches);
      return values;
    });

    final output = <Book>[...exact.map((item) => item.book)];
    while (output.length < ranked.length) {
      final slot = output.length % 20;
      final preferred = slot < 10 ? 0 : (slot < 15 ? 1 : 2);
      final fallbackOrder = switch (preferred) {
        0 => const [0, 1, 2, 3],
        1 => const [1, 2, 0, 3],
        _ => const [2, 1, 0, 3],
      };
      _RankedBook? next;
      for (final bucketIndex in fallbackOrder) {
        if (buckets[bucketIndex].isNotEmpty) {
          next = buckets[bucketIndex].removeAt(0);
          break;
        }
      }
      if (next == null) break;
      output.add(next.book);
    }
    return output;
  }

  List<Book> _filterForViewer(List<Book> books) =>
      ContentSafetyService.filterBooks(
        books, allowAdultContent: allowAdultContent,
      );

  /// The home page keeps 9 cards, the three existing section labels and
  /// previous/next controls. Popular is now first-party review popularity.
  Future<List<Book>> fetchBooksByGenre(String genre, {int page = 1}) async {
    try {
      if (genre.contains('ベストセラー') || genre.contains('人気')) {
        final ranked = await (_popularCache ??=
            SupabaseService().fetchPopularBooks(limit: 200));
        final start = (page - 1) * 9;
        if (start >= ranked.length) return const <Book>[];
        final chosen = ranked.skip(start).take(9).toList(growable: false);
        return _filterForViewer(await OpenBdApi.enrich(chosen));
      }
      // Do not silently skip 21 out of every 30 new-arrival records when
      // the home section displays nine books per page.
      final window = genre.contains('新着') ? 9 : 30;
      final incoming = await NdlApi.searchBySelectedGenre(
        selectedGenre: genre, page: page, count: window,
      );
      final enriched = await OpenBdApi.enrich(incoming);
      final filtered = _filterForViewer(enriched);
      if (genre.contains('新着')) {
        // The source is NDL in-process records, not a release-day feed.
        // Sort the returned *page*, never claim a global release-date sort.
        filtered.sort((a, b) => b.pubDate.compareTo(a.pubDate));
        return filtered.take(9).toList(growable: false);
      }
      return _randomRankedSelection(filtered, count: 9);
    } catch (_) {
      return const <Book>[];
    }
  }

  List<Book> _randomRankedSelection(List<Book> ranked, {
    required int count,
  }) {
    if (ranked.length <= count) return List<Book>.from(ranked);
    final indexes = List<int>.generate(ranked.length, (index) => index)
      ..shuffle(_homeRandom);
    indexes
      ..removeRange(count, indexes.length)
      ..sort();
    return indexes.map((index) => ranked[index]).toList(growable: false);
  }

  Future<List<Book>> fetchAllBooks() async {
    try {
      final books = await NdlApi.search(
        any: '本', provider: NdlApi.national, count: 20,
      );
      return _filterForViewer(await OpenBdApi.enrich(books));
    } catch (_) {
      return const <Book>[];
    }
  }

  void _resetSearch(String query) {
    _activeQuery = query;
    _nextSearchPage = 1;
    _searchSeenIds.clear();
    final fields = searchFieldPriority(query);
    final variants = _keywordVariants(query);
    _cursors = fields.map((field) =>
        _NdlFieldCursor(field, variants)).toList(growable: false);
  }

  Future<NdlSearchBatch> _fetchField(
    _NdlFieldCursor cursor, int start, int count,
  ) {
    if (fieldFetcher != null) {
      return fieldFetcher!(cursor.field, cursor.variant,
          cursor.provider, start, count);
    }
    return NdlApi.searchPage(
      title: cursor.field == BookSearchField.title ? cursor.variant : null,
      creator: cursor.field == BookSearchField.author ? cursor.variant : null,
      publisher: cursor.field == BookSearchField.publisher ? cursor.variant : null,
      provider: cursor.provider,
      start: start,
      count: count,
    );
  }

  /// Pull results from a source cursor without losing the unused half of a
  /// source page. Only upstream rawCount advances the NDL offset; ISBN-less
  /// records still occupy upstream slots.
  Future<List<Book>> _takeFromCursor(
    _NdlFieldCursor cursor, int wanted,
  ) async {
    final collected = <Book>[];
    var upstreamRequests = 0;
    while (collected.length < wanted) {
      if (cursor.buffer.isNotEmpty) {
        final book = cursor.buffer.removeAt(0);
        if (_searchSeenIds.add(book.id)) collected.add(book);
        continue;
      }
      if (cursor.finished || upstreamRequests >= 3) break;
      if (cursor.offset > 480) {
        cursor.nextVariantOrProvider();
        continue;
      }
      final requestCount = min(20, 501 - cursor.offset);
      if (requestCount < 1) {
        cursor.nextVariantOrProvider();
        continue;
      }
      final batch = await _fetchField(
        cursor, cursor.offset, requestCount,
      );
      upstreamRequests++;
      cursor.offset += batch.rawCount;
      cursor.buffer.addAll(batch.books);
      if (!batch.hasMore || batch.rawCount == 0) {
        cursor.nextVariantOrProvider();
      }
    }
    return collected;
  }

  /// Stable cursor-based pagination with existing title/author/publisher
  /// priority and 10/5/5 allocation for a 20-book result page. This avoids
  /// discarding items #11-20 after fetching 20 upstream records for 10 slots.
  Future<BookSearchBatch> searchBooksPage(
    String query, {int page = 1, int count = 20}
  ) async {
    final clean = query.trim();
    if (clean.isEmpty) {
      return BookSearchBatch(books: await fetchAllBooks(), hasMore: false);
    }
    if (!allowAdultContent &&
        ContentSafetyService.isAdultSearchQuery(clean)) {
      return const BookSearchBatch(books: [], hasMore: false);
    }
    if (page == 1 || clean != _activeQuery || page != _nextSearchPage) {
      _resetSearch(clean);
    }
    final quotas = <int>[
      (count * 0.5).ceil(),
      (count * 0.25).ceil(),
      count - (count * 0.5).ceil() - (count * 0.25).ceil(),
    ];
    final candidates = <Book>[];
    try {
      for (var i = 0; i < _cursors.length; i++) {
        candidates.addAll(await _takeFromCursor(_cursors[i], quotas[i]));
      }
      // If one field is exhausted, fill its spare slots from the others.
      var attemptsWithoutProgress = 0;
      while (candidates.length < count && attemptsWithoutProgress < 3) {
        var madeProgress = false;
        for (final cursor in _cursors) {
          if (candidates.length >= count) break;
          final next = await _takeFromCursor(cursor, 1);
          if (next.isNotEmpty) {
            candidates.addAll(next);
            madeProgress = true;
          }
        }
        if (madeProgress) {
          attemptsWithoutProgress = 0;
        } else {
          attemptsWithoutProgress++;
        }
      }
      _nextSearchPage = page + 1;
      final enriched = await OpenBdApi.enrich(candidates);
      final filtered = _filterForViewer(enriched);
      final result = rankSearchResults(filtered, clean)
          .take(count).toList(growable: false);
      final more = result.isNotEmpty && _cursors.any(
        (cursor) => cursor.buffer.isNotEmpty || !cursor.finished,
      );
      return BookSearchBatch(books: result, hasMore: more);
    } catch (_) {
      return const BookSearchBatch(books: [], hasMore: false);
    }
  }

  /// Compatibility entrypoint for admin lookup and existing search screens.
  Future<List<Book>> searchBooks(
    String query, {int page = 1, int count = 20}
  ) async => (await searchBooksPage(query, page: page, count: count)).books;

  static List<String> _keywordVariants(String query) {
    final original = query.trim();
    final compact = original.replaceAll(RegExp(r'[\s\u3000・･]+'), '');
    final variants = <String>{original, compact};
    final segments = original.split(RegExp(r'[\s\u3000・･]+'))
        .where((part) => part.length >= 2).toList();
    if (RegExp(r'[・･]').hasMatch(original) && segments.length > 1) {
      variants.add(segments.first);
    } else if (compact.length > 6 &&
        RegExp(r'[ぁ-んァ-ヶ一-龥]').hasMatch(compact)) {
      variants.add(compact.substring(0, 6));
    }
    return variants.where((x) => x.isNotEmpty).toList(growable: false);
  }

}

class _RankedBook {
  const _RankedBook({
    required this.book,
    required this.priorityIndex,
    required this.quality,
    this.isExact = false,
  });

  final Book book;
  final int priorityIndex;
  final int quality;
  final bool isExact;
}

class _NdlFieldCursor {
  _NdlFieldCursor(this.field, this.variants);
  final BookSearchField field;
  final List<String> variants;
  final List<Book> buffer = <Book>[];
  int offset = 1;
  int providerIndex = 0;
  int variantIndex = 0;
  bool finished = false;

  String get provider =>
      providerIndex == 0 ? NdlApi.national : NdlApi.inProcess;
  String get variant => variants[variantIndex];

  void nextVariantOrProvider() {
    if (variantIndex + 1 < variants.length) {
      variantIndex++;
    } else if (providerIndex == 0) {
      providerIndex = 1;
      variantIndex = 0;
    } else {
      finished = true;
    }
    offset = 1;
  }
}
