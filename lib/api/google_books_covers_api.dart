import 'dart:convert';

import 'package:http/http.dart' as http;
import '../models/book.dart';

/// Optional, low-volume Google Books Dynamic Links cover enrichment.
/// The worker verifies ISBN identity and source host and returns both the
/// thumbnail and its required Google Books info-page attribution link.
class GoogleBooksCoversApi {
  static const batchSize = 25;

  static bool _safeGoogleUrl(String input, {required bool image}) {
    final url = Uri.tryParse(input);
    if (url == null || url.scheme != 'https' ||
        url.userInfo.isNotEmpty || url.hasPort) return false;
    const imageHosts = {'books.google.com', 'books.googleusercontent.com'};
    return image ? imageHosts.contains(url.host) :
        url.host == 'books.google.com';
  }

  /// Pure transform: source credit is mandatory. Never silently substitute a
  /// title-similar cover for an edition's ISBN.
  static Book enrichRecord(Book book, Map<String, dynamic> record) {
    if (book.coverUrl.trim().isNotEmpty) return book;
    final coverUrl = record['coverUrl']?.toString() ?? '';
    final creditUrl = record['creditUrl']?.toString() ?? '';
    if (!_safeGoogleUrl(coverUrl, image: true) ||
        !_safeGoogleUrl(creditUrl, image: false)) return book;
    return book.copyWith(
      coverUrl: coverUrl,
      coverSource: 'google_books',
      coverAttributionUrl: creditUrl,
    );
  }

  static Future<List<Book>> enrich(List<Book> books) async {
    final isbns = books
        .where((book) => book.coverUrl.trim().isEmpty &&
            RegExp(r'^97[89]\d{10}$').hasMatch(book.isbn))
        .map((book) => book.isbn)
        .toSet().toList(growable: false);
    if (isbns.isEmpty) return books;

    final covers = <String, Map<String, dynamic>>{};
    for (var start = 0; start < isbns.length; start += batchSize) {
      final chunk = isbns.skip(start).take(batchSize).toList(growable: false);
      try {
        final response = await http.get(Uri(
          path: '/api/book-covers',
          queryParameters: {'isbn': chunk.join(',')},
        )).timeout(const Duration(seconds: 11));
        if (response.statusCode != 200) continue;
        final json = jsonDecode(utf8.decode(response.bodyBytes));
        if (json is! Map || json['covers'] is! Map) continue;
        final byIsbn = json['covers'] as Map;
        for (final isbn in chunk) {
          final row = byIsbn[isbn];
          if (row is Map<String, dynamic>) covers[isbn] = row;
        }
      } catch (_) {
        // Cover metadata is optional. Preserve NDL records and original
        // jackets, even if Google Books is unavailable or rate-limited.
      }
    }
    return books.map((book) {
      final record = covers[book.isbn];
      return record == null ? book : enrichRecord(book, record);
    }).toList(growable: false);
  }
}
