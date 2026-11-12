import '../models/book.dart';
import 'ndl_api.dart';
import 'openbd_api.dart';
import 'rakuten_api.dart';

typedef BookIdFetcher = Future<Book?> Function(String bookId);
typedef BookEnricher = Future<List<Book>> Function(List<Book> books);

/// Cloudflare production and staging use exact Rakuten lookup. Other builds
/// retain their existing NDL/openBD behavior as a rollback path.
class BookCatalogLookup {
  const BookCatalogLookup({
    this.useRakuten = const bool.fromEnvironment(
      'RAKUTEN_CATALOG',
      defaultValue: bool.fromEnvironment(
        'STAGING_RAKUTEN_CATALOG',
        defaultValue: false,
      ),
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
      // Never attach a different edition's Rakuten metadata to a saved ISBN.
      final requestedIsbn = bookId.replaceAll('-', '').toUpperCase();
      if (RegExp(r'^(?:\d{13}|\d{9}[\dX])$').hasMatch(requestedIsbn) &&
          book.isbn.replaceAll('-', '').toUpperCase() != requestedIsbn) {
        return null;
      }
      // Prefer openBD when it has a cover. Otherwise retain the image URL
      // supplied by the Rakuten Books API for this exact ISBN.
      final enriched = await (openBdEnricher ?? OpenBdApi.enrich)([book]);
      return enriched.isEmpty ? book : enriched.first;
    }

    final book = await (ndlFetcher ?? NdlApi.fetchBookById)(bookId);
    if (book == null || !enrichNdl) return book;
    final enriched = await (openBdEnricher ?? OpenBdApi.enrich)([book]);
    return enriched.isEmpty ? book : enriched.first;
  }
}
