import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/api/rakuten_api.dart';
import 'package:sharemarium/repositories/book_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book({
  required String id,
  required String title,
  required String author,
  required String publisher,
  int reviewCount = 0,
  double ratingAvg = 0,
}) {
  return Book(
    id: id,
    title: title,
    author: author,
    publisher: publisher,
    pubDate: '',
    isbn: id,
    coverUrl: '',
    reviewCount: reviewCount,
    ratingAvg: ratingAvg,
  );
}

void main() {

  test('4/3/3 means display allocation, not an upstream fetch limit', () async {
    final limits = <String, int>{};
    final batch = await RakutenApi.searchByKeywordPage(
      keyword: '芥川',
      count: 10,
      searchFields: const ['author', 'title', 'publisherName'],
      fieldSearch: (field, term, page, limit) async {
        limits[field] = limit;
        if (field == 'publisherName') return [];
        return List.generate(field == 'author' ? 8 : 5, (i) => _book(
          id: '$field-$i',
          title: field == 'title' ? '芥川 Book $i' : 'Book $i',
          author: field == 'author' ? '芥川龍之介' : 'Another Writer',
          publisher: 'Publisher',
        ));
      },
    );
    expect(limits, {'author': 10, 'title': 10, 'publisherName': 10});
    expect(batch.books.length, 13);
    expect(batch.hasMore, isFalse, reason: 'No field filled its upstream page');
    final ranked = BookRepository.rankSearchResults(batch.books, '芥川');
    expect(ranked.take(10).length, 10);
  });

  test('full author upstream page keeps continuation after only 7 unique matches', () async {
    final batch = await RakutenApi.searchByKeywordPage(
      keyword: '芥川',
      count: 10,
      searchFields: const ['author', 'title', 'publisherName'],
      fieldSearch: (field, term, page, limit) async {
        if (field == 'author') {
          return List.generate(10, (i) => _book(
            id: 'author-$i', title: 'Story $i', author: '芥川龍之介',
            publisher: 'Publisher',
          ));
        }
        return [];
      },
    );
    expect(batch.hasMore, isTrue);
  });

  test('楽天検索は4/3/3件に割り当て、通常は最大3回のリクエスト', () async {
    final calls = <String>[];
    final found = await RakutenApi.searchByKeyword(
      keyword: '芥川',
      count: 10,
      searchFields: const ['author', 'title', 'publisherName'],
      fieldSearch: (field, term, page, limit) async {
        calls.add('$field:$term:$limit');
        return List.generate(limit, (i) => _book(
          id: '$field-$i',
          title: term,
          author: '芥川龍之介',
          publisher: '出版社',
        ));
      },
    );
    expect(calls, [
      'author:芥川:4',
      'title:芥川:3',
      'publisherName:芥川:3',
    ]);
    expect(found.length, 10);
  });

  test('楽天検索は途中のフィールドが障害でも取得済みの本を破棄しない', () async {
    final calls = <String>[];
    final found = await RakutenApi.searchByKeyword(
      keyword: '芥川',
      count: 10,
      searchFields: const ['author', 'title', 'publisherName'],
      fieldSearch: (field, term, page, limit) async {
        calls.add(field);
        if (field == 'title') throw StateError('upstream unavailable');
        return [_book(id: '9780000000001', title: '羅生門', author: '芥川龍之介', publisher: '出版社')];
      },
    );
    expect(found.length, 1);
    expect(found.single.title, '羅生門');
    expect(calls, ['author', 'title']);
  });

  test('楽天検索は全フィールド障害時にNDLの代替検索へ例外を返す', () async {
    await expectLater(
      RakutenApi.searchByKeyword(
        keyword: '芥川',
        fieldSearch: (_, __, ___, ____) async =>
          throw StateError('upstream unavailable'),
      ),
      throwsStateError,
    );
  });

  test('楽天検索は表記違いを試しつつ最大5回で打ち切る', () async {
    final calls = <String>[];
    await RakutenApi.searchByKeyword(
      keyword: 'プロジェクト・へイル・メアリー',
      count: 10,
      fieldSearch: (field, term, page, limit) async {
        calls.add('$field:$term');
        return const [];
      },
    );
    expect(calls.length, lessThanOrEqualTo(5));
    expect(calls.toSet().length, calls.length);
  });

  test('楽天検索ではスペースと中点を除いた検索語も生成する', () {
    expect(RakutenApi.buildSearchKeywordVariants('プロジェクト・へイル・メアリー'), [
      'プロジェクト・へイル・メアリー',
      'プロジェクトへイルメアリー',
      'プロジェクト',
    ]);
    expect(RakutenApi.buildSearchKeywordVariants('プロジェクトへイル'), [
      'プロジェクトへイル',
      'プロジェクト',
    ]);
    expect(RakutenApi.buildSearchKeywordVariants('Andy Weir'), [
      'Andy Weir',
      'AndyWeir',
    ]);
  });

  group('検索入力の分類', () {
    test('社で終わる場合は出版社を優先する', () {
      expect(
        BookRepository.searchFieldPriority('講談社').first,
        BookSearchField.publisher,
      );
    });

    test('社で終わらない漢字だけの検索語は文字数にかかわらず著者を優先する', () {
      for (final query in ['海', '三体', '村上春樹', '日本文学研究', '佐々木']) {
        expect(
          BookRepository.searchFieldPriority(query),
          [
            BookSearchField.author,
            BookSearchField.title,
            BookSearchField.publisher,
          ],
          reason: '漢字のみの入力: $query',
        );
      }
    });

    test('社で終わる漢字だけの文字列は引き続き出版社を優先する', () {
      expect(
        BookRepository.searchFieldPriority('講談社'),
        [BookSearchField.publisher, BookSearchField.title, BookSearchField.author],
      );
    });

    test('仮名混じりの検索語は既存の分類を維持する', () {
      expect(BookRepository.searchFieldPriority('君の名は').first, BookSearchField.author);
      expect(BookRepository.searchFieldPriority('あ').first, BookSearchField.title);
    });

    test('スペースなし3〜5文字の日本語は著者を優先する', () {
      expect(
        BookRepository.searchFieldPriority('村上春樹').first,
        BookSearchField.author,
      );
    });

    test('カタカナ・カタカナは著者を優先する', () {
      expect(
        BookRepository.searchFieldPriority('アンディ・ウィアー').first,
        BookSearchField.author,
      );
    });

    test('漢字のみ以外の長い書名はタイトルを優先する', () {
      expect(
        BookRepository.searchFieldPriority('プロジェクトヘイルメアリー').first,
        BookSearchField.title,
      );
    });

    test('英語の記号入りはタイトルを優先する', () {
      expect(
        BookRepository.searchFieldPriority('What If?').first,
        BookSearchField.title,
      );
    });

    test('英単語2語は著者を優先する', () {
      expect(
        BookRepository.searchFieldPriority('Andy Weir').first,
        BookSearchField.author,
      );
    });

    test('Co.またはcomicsで終わる場合は出版社を優先する', () {
      expect(
        BookRepository.searchFieldPriority('Kodansha Co.').first,
        BookSearchField.publisher,
      );
      expect(
        BookRepository.searchFieldPriority('Marvel Comics').first,
        BookSearchField.publisher,
      );
    });
  });

  test('スペースや中点を除いた完全一致は部分一致より先に並ぶ', () {
    final ranked = BookRepository.rankSearchResults([
      _book(
        id: 'contains',
        title: 'アンディ・ウィアー傑作集',
        author: '別人',
        publisher: '出版社',
        reviewCount: 100,
      ),
      _book(id: 'exact', title: '別の本', author: 'アンディウィアー', publisher: '出版社'),
    ], 'アンディ・ウィアー');

    expect(ranked.first.id, 'exact');
  });

  test('漢字のみの書名もタイトル完全一致なら著者の部分一致より先に表示される', () {
    final ranked = BookRepository.rankSearchResults([
      _book(
        id: 'author-match',
        title: '別の書名',
        author: '三体研究会',
        publisher: '架空出版',
        reviewCount: 1000,
      ),
      _book(
        id: 'title-exact',
        title: '三体',
        author: '劉慈欣',
        publisher: '早川書房',
      ),
    ], '三体');

    expect(ranked.first.id, 'title-exact');
  });

  test('中点の有無が異なるタイトルも完全一致として扱う', () {
    final ranked = BookRepository.rankSearchResults([
      _book(
        id: 'match',
        title: 'プロジェクト・へイル・メアリー',
        author: 'アンディ・ウィアー',
        publisher: '早川書房',
      ),
      _book(
        id: 'partial',
        title: 'プロジェクトへイルメアリー読本',
        author: '別の著者',
        publisher: '別の出版社',
        reviewCount: 100,
      ),
    ], 'プロジェクトへイルメアリー');

    expect(ranked.first.id, 'match');
  });

  test('最初の10冊を優先度1に4冊、優先度2に3冊、優先度3に3冊配分する', () {
    final books = <Book>[
      for (var i = 0; i < 12; i++)
        _book(
          id: 'author-$i',
          title: '別の本$i',
          author: '村上春樹作品$i',
          publisher: '別の出版社',
          reviewCount: 100 - i,
        ),
      for (var i = 0; i < 7; i++)
        _book(
          id: 'title-$i',
          title: '村上春樹を読む$i',
          author: '別の著者$i',
          publisher: '別の出版社',
          reviewCount: 100 - i,
        ),
      for (var i = 0; i < 7; i++)
        _book(
          id: 'publisher-$i',
          title: '別の本$i',
          author: '別の著者$i',
          publisher: '村上春樹出版$i',
          reviewCount: 100 - i,
        ),
    ];

    final ranked = BookRepository.rankSearchResults(books, '村上春樹');

    expect(
      ranked.take(4).every((book) => book.id.startsWith('author-')),
      isTrue,
    );
    expect(
      ranked.skip(4).take(3).every((book) => book.id.startsWith('title-')),
      isTrue,
    );
    expect(
      ranked.skip(7).take(3).every((book) => book.id.startsWith('publisher-')),
      isTrue,
    );
  });

  test('優先度3の候補がない場合は優先度2で枠を補う', () {
    final books = <Book>[
      for (var i = 0; i < 10; i++)
        _book(
          id: 'author-$i',
          title: '別の本$i',
          author: '村上春樹作品$i',
          publisher: '別の出版社',
        ),
      for (var i = 0; i < 10; i++)
        _book(
          id: 'title-$i',
          title: '村上春樹を読む$i',
          author: '別の著者$i',
          publisher: '別の出版社',
        ),
    ];

    final ranked = BookRepository.rankSearchResults(books, '村上春樹');
    expect(
      ranked.skip(4).take(6).every((book) => book.id.startsWith('title-')),
      isTrue,
    );
  });

  test('同じ優先度と一致度では楽天レビュー件数が多い本を優先する', () {
    final ranked = BookRepository.rankSearchResults([
      _book(
        id: 'less-popular',
        title: '検索する本 A',
        author: '著者',
        publisher: '出版社',
        reviewCount: 3,
      ),
      _book(
        id: 'popular',
        title: '検索する本 B',
        author: '著者',
        publisher: '出版社',
        reviewCount: 120,
      ),
    ], '検索する本');

    expect(ranked.first.id, 'popular');
  });
}
