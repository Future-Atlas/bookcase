import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import 'ndl_api.dart';

/// A lightweight, read-only source for the home 和書 / 洋書 sections.
/// No Supabase book catalogue. API verifies each edition's real ISBN and
/// explicit language before the client accepts it; all images still use the
/// separate approved publisher/openBD cover policy.
class HomeCatalogApi {
  static const windowSize = 60;

  static Uri searchUri({
    required String language,
    required String topic,
    required int start,
  }) => Uri(path: '/api/home-catalog', queryParameters: {
    'lang': language,
    'topic': topic,
    'page': (((start - 1) ~/ windowSize) + 1).toString(),
  });

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
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
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
        if (!RegExp(r'^97[89]\d{10}$').hasMatch(isbn) ||
            explicitLanguage != language || title.isEmpty || !seen.add(isbn)) {
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
        rawCount: rawCount.clamp(0, windowSize),
        hasMore: decoded['hasMore'] == true,
      );
    } catch (_) {
      return const NdlSearchBatch(
        books: [], rawCount: 0, hasMore: false,
        temporarilyUnavailable: true,
      );
    }
  }
}
