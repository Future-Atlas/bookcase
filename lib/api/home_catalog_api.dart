import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'ndl_api.dart';

/// Low-volume, read-only home catalog. No Supabase metadata storage.
/// The server verifies each edition's explicit language and ISBN.
class HomeCatalogApi {
  static const windowSize = 27;

  static Uri searchUri({
    required String language,
    required String topic,
    required int start,
  }) => Uri(path: '/api/home-catalog', queryParameters: {
    'lang': language,
    'topic': topic,
    'page': (((start - 1) ~/ windowSize) + 1).toString(),
  });

  static bool _validIsbn13(String value) {
    if (!RegExp(r'^97[89]\d{10}$').hasMatch(value)) return false;
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(value[i]) * (i.isOdd ? 3 : 1);
    }
    return (10 - sum % 10) % 10 == int.parse(value[12]);
  }

  /// Pure decoder for regression tests and fail-closed client validation.
  /// Never accept work-level language, missing ISBNs, or fabricated covers.
  static NdlSearchBatch parseDecoded(Object? decoded, {
    required String language, String genre = '',
  }) {
    if (decoded is! Map || decoded['books'] is! List ||
        decoded['catalogSource'] != 'openlibrary') {
      return const NdlSearchBatch(
        books: [], rawCount: 0, hasMore: false,
        temporarilyUnavailable: true,
      );
    }
    final books = <Book>[];
    final seen = <String>{};
    for (final row in decoded['books'] as List) {
      if (row is! Map) continue;
      final isbn = row['isbn']?.toString() ?? '';
      final explicitLanguage = row['languageCode']?.toString() ?? '';
      final title = row['title']?.toString().trim() ?? '';
      if (!_validIsbn13(isbn) || explicitLanguage != language ||
          title.isEmpty || !seen.add(isbn)) {
        continue;
      }
      books.add(Book(
        id: isbn,
        isbn: isbn,
        title: title,
        author: row['author']?.toString() ?? '',
        publisher: row['publisher']?.toString() ?? '',
        pubDate: row['pubDate']?.toString() ?? '',
        coverUrl: '',
        genre: genre,
        languageCode: explicitLanguage,
        catalogSource: 'openlibrary',
        catalogFetchedAt: DateTime.now().toUtc(),
      ));
    }
    final count = decoded['rawCount'];
    final rawCount = count is num ? count.toInt() : 0;
    return NdlSearchBatch(
      books: books,
      rawCount: rawCount.clamp(0, windowSize).toInt(),
      hasMore: decoded['hasMore'] == true,
    );
  }

  static Future<NdlSearchBatch> searchPage({
    required String language,
    required String topic,
    required int start,
    String genre = '',
  }) async {
    if (!const {'eng', 'jpn'}.contains(language) || start < 1 || start > 500) {
      return const NdlSearchBatch(
        books: [], rawCount: 0, hasMore: false,
      );
    }
    try {
      final response = await http.get(searchUri(
        language: language, topic: topic, start: start,
      )).timeout(const Duration(seconds: 22));
      if (response.statusCode != 200) {
        return NdlSearchBatch(
          books: const [], rawCount: 0, hasMore: false,
          temporarilyUnavailable: response.statusCode == 429 ||
              response.statusCode >= 500,
        );
      }
      return parseDecoded(
        jsonDecode(utf8.decode(response.bodyBytes)),
        language: language, genre: genre,
      );
    } catch (_) {
      return const NdlSearchBatch(
        books: [], rawCount: 0, hasMore: false,
        temporarilyUnavailable: true,
      );
    }
  }
}
