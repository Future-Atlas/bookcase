import '../models/book.dart';
import 'ndl_api.dart';
import 'openbd_api.dart';
import 'rakuten_api.dart';

typedef BookIdFetcher = Future<Book?> Function(String bookId);
typedef BookEnricher = Future<List<Book>> Function(List<Book> books);

/// Match the production Rakuten book lookup in staging. Other builds retain
/// their existing NDL/openBD behavior for rollback and non-staging use.
class BookCatalogLookup {
  const BookCatalogLookup({
    this.useRakuten = const bool.fromEnvironment(
      'STAGING_RAKUTEN_CATALOG', defaultValue: false,
    ),
    this.rakutenFetcher,
    this.ndlFetcher,
    this.openBdEnricher,
  });

  final bool useRakuten;
  final BookIdFetcher? rakutenFetcher;
  final BookIdFetcher? ndlFetcher;
  final BookEnricher? openBdEnricher;

  Future<Book?> fetchById(String id, {bool enrichNdl = false}) async {
    final bookId = id.trim();
    if (bookId.isEmpty) return null;
    if (useRakuten) {
      // Fail closed: a provider 403/5xx must not silently switch to NDL.
      final book = await (rakutenFetcher ?? RakutenApi.fetchBookById)(bookId);
      if (book == null) return null;
      // Retailer thumbnails are not independently licensed for display.
      // Publisher-verified covers are selected by the existing BookCoverImage.
      return book.copyWith(
        coverUrl: book.coverSource == 'openbd' ? book.coverUrl : '',
        coverAttributionUrl: book.coverSource == 'openbd'
            ? book.coverAttributionUrl : '',
      );
    }

    final book = await (ndlFetcher ?? NdlApi.fetchBookById)(bookId);
    if (book == null || !enrichNdl) return book;
    final enriched = await (openBdEnricher ?? OpenBdApi.enrich)([book]);
    return enriched.isEmpty ? book : enriched.first;
  }
}
