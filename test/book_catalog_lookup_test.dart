import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/book_catalog_lookup.dart';
import 'package:sharemarium/models/book.dart';

Book sample(String id, {String coverUrl = ''}) => Book(
  id: id,
  isbn: id,
  title: 'Book $id',
  author: 'Author',
  publisher: 'Publisher',
  pubDate: '',
  coverUrl: coverUrl,
  catalogSource: 'rakuten',
);

void main() {
  test('staging uses only Rakuten for book detail and strips retailer art', () async {
    final calls = <String>[];
    final lookup = BookCatalogLookup(
      useRakuten: true,
      rakutenFetcher: (id) async {
        calls.add('rakuten:$id');
        return sample(id, coverUrl: 'https://thumbnail.image.rakuten.co.jp/x.jpg');
      },
      ndlFetcher: (_) async => throw StateError('NDL must not run'),
      openBdEnricher: (_) async => throw StateError('NDL enrichment must not run'),
    );
    final book = await lookup.fetchById('9784000000001', enrichNdl: true);
    expect(book?.title, 'Book 9784000000001');
    expect(book?.coverUrl, isEmpty);
    expect(calls, ['rakuten:9784000000001']);
  });

  test('staging rejects a mismatched ISBN response', () async {
    final lookup = BookCatalogLookup(
      useRakuten: true,
      rakutenFetcher: (_) async => sample('9784000000002'),
    );
    expect(await lookup.fetchById('9784000000001'), isNull);
  });

  test('staging does not fall back to NDL on provider failure', () async {
    final lookup = BookCatalogLookup(
      useRakuten: true,
      rakutenFetcher: (_) async => null,
      ndlFetcher: (_) async => throw StateError('not an NDL fallback'),
    );
    expect(await lookup.fetchById('9784000000001'), isNull);
  });

  test('non-staging retains NDL and openBD enrichment', () async {
    var calls = 0;
    final lookup = BookCatalogLookup(
      useRakuten: false,
      ndlFetcher: (id) async {
        calls++;
        return sample(id);
      },
      openBdEnricher: (books) async {
        calls++;
        return books;
      },
      rakutenFetcher: (_) async => throw StateError('not staging'),
    );
    expect((await lookup.fetchById('9784000000001', enrichNdl: true))?.id,
        '9784000000001');
    expect(calls, 2);
  });

  test('blank identifiers never reach provider APIs', () async {
    final lookup = BookCatalogLookup(
      useRakuten: true,
      rakutenFetcher: (_) async => throw StateError('empty ID leaked'),
    );
    expect(await lookup.fetchById('  '), isNull);
  });
}
