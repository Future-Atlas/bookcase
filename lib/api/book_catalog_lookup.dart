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

  // Older shelves may store an ISBN-10, while Rakuten returns ISBN-13 for
  // the same edition. Only convert a checksum-valid ISBN, never a title.
  static String _catalogId(String id) {
    final digits = id.replaceAll('-', '').toUpperCase();
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(digits)) return id;
    var sum = 0;
    for (var i = 0; i < 10; i++) {
      sum += (digits[i] == 'X' ? 10 : int.parse(digits[i])) * (10 - i);
    }
    if (sum % 11 != 0) return id;
    final prefix = '978${digits.substring(0, 9)}';
    var weighted = 0;
    for (var i = 0; i < prefix.length; i++) {
      weighted += int.parse(prefix[i]) * (i.isEven ? 1 : 3);
    }
    return '$prefix${(10 - weighted % 10) % 10}';
  }

  Future<Book?> fetchById(String id, {bool enrichNdl = false}) async {
    final bookId = id.trim();
    if (bookId.isEmpty) return null;
    if (useRakuten) {
      // Fail closed: a provider 403/5xx must not silently switch to NDL.
      final lookupId = _catalogId(bookId);
      final book = await (rakutenFetcher ?? RakutenApi.fetchBookById)(lookupId);
      if (book == null) return null;
      // Never attach a different edition's Rakuten metadata to a saved ISBN.
      final requestedIsbn = lookupId.replaceAll('-', '').toUpperCase();
      if (RegExp(r'^(?:\d{13}|\d{9}[\dX])$').hasMatch(requestedIsbn) &&
          book.isbn.replaceAll('-', '').toUpperCase() != requestedIsbn) {
        return null;
      }
      // Prefer openBD when it has a cover. Otherwise retain the image URL
      // supplied by the Rakuten Books API for this exact ISBN.
      final enriched = await (openBdEnricher ?? OpenBdApi.enrich)([book]);
      final resolved = enriched.isEmpty ? book : enriched.first;
      return lookupId == bookId ? resolved : resolved.copyWith(id: bookId);
    }

    final book = await (ndlFetcher ?? NdlApi.fetchBookById)(bookId);
    if (book == null || !enrichNdl) return book;
    final enriched = await (openBdEnricher ?? OpenBdApi.enrich)([book]);
    return enriched.isEmpty ? book : enriched.first;
  }
}
