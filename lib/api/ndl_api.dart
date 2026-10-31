import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/book.dart';

/// Search only NDL OpenSearch records. Reuse the same page and genre labels
/// used by the existing home/search UI.
class NdlApi {
  static const _base = '/api/ndl';

  static Uri searchUri({
    String? any,
    String? title,
    String? creator,
    String? publisher,
    String? isbn,
    String? ndc,
    String provider = 'iss-ndl-opac-national',
    int page = 1,
    int count = 20,
  }) => Uri(path: _base, queryParameters: {
    'dpid': provider,
    'idx': '${(page - 1) * count + 1}',
    'cnt': '$count',
    if (any != null && any.isNotEmpty) 'any': any,
    if (title != null && title.isNotEmpty) 'title': title,
    if (creator != null && creator.isNotEmpty) 'creator': creator,
    if (publisher != null && publisher.isNotEmpty) 'publisher': publisher,
    if (isbn != null && isbn.isNotEmpty) 'isbn': isbn,
    if (ndc != null && ndc.isNotEmpty) 'ndc': ndc,
  });

  static Future<List<Book>> search({
    String? any,
    String? title,
    String? creator,
    String? publisher,
    String? isbn,
    String? ndc,
    String provider = 'iss-ndl-opac-national',
    int page = 1,
    int count = 20,
    String genre = '',
  }) async {
    if (page < 1 || count < 1) return [];
    try {
      final response = await http.get(searchUri(
        any: any, title: title, creator: creator, publisher: publisher,
        isbn: isbn, ndc: ndc, provider: provider, page: page, count: count,
      )).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      return parseBooks(utf8.decode(response.bodyBytes), genre: genre);
    } catch (_) {
      return [];
    }
  }

  static String? _value(XmlElement item, List<String> names) {
    for (final name in names) {
      final local = name.split(':').last;
      for (final child in item.children.whereType<XmlElement>()) {
        if (child.name.local == local) {
          final value = child.innerText.trim();
          if (value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }

  static List<Book> parseBooks(String xml, {String genre = ''}) {
    final doc = XmlDocument.parse(xml);
    final results = <Book>[];
    final seen = <String>{};
    for (final item in doc.findAllElements('item')) {
      final title = _value(item, ['title', 'dc:title']) ?? '';
      if (title.isEmpty) continue;
      String isbn = '';
      for (final identifier in item.children.whereType<XmlElement>()
          .where((element) => element.name.local == 'identifier')) {
        final raw = identifier.innerText.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
        if (RegExp(r'^(?:[0-9]{13}|[0-9]{9}[0-9X])$').hasMatch(raw)) {
          isbn = raw;
          break;
        }
      }
      // Existing shelves and review joins are keyed on ISBN: avoid
      // unstable generated IDs and non-ISBN records in the main catalog.
      if (isbn.isEmpty || !seen.add(isbn)) continue;
      results.add(Book(
        id: isbn, isbn: isbn, title: title,
        author: _value(item, ['dc:creator', 'author']) ?? '',
        publisher: _value(item, ['dc:publisher']) ?? '',
        pubDate: _value(item, ['dcterms:issued', 'dc:date']) ?? '',
        coverUrl: '', genre: genre,
        description: _value(item, ['dc:description']) ?? '',
        catalogSource: 'ndl',
        catalogFetchedAt: DateTime.now().toUtc(),
      ));
    }
    return results;
  }

  /// Exact ISBN lookup used when a saved book/post needs fresh metadata.
  /// Returning null leaves persistent user data and its title fallback intact.
  static Future<Book?> fetchBookById(String id) async {
    final isbn = id.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (!RegExp(r'^(?:[0-9]{13}|[0-9]{9}[0-9X])
    required String selectedGenre,
    int page = 1,
    int count = 10,
  }) {
    String? ndc;
    String? any;
    if (selectedGenre.contains('新着') || selectedGenre.contains('おすすめ')) {
      // NDL search has no Rakuten equivalent for release-date ranking.
      // Published-date sorting is performed by BookRepository.
      any = '本';
    } else if (selectedGenre.contains('English') || selectedGenre.contains('洋書')) {
      any = 'English';
    } else if (selectedGenre.contains('ベストセラー') || selectedGenre.contains('人気') ||
               selectedGenre.contains('話題')) {
      any = '本';
    } else if (selectedGenre.contains('文学') || selectedGenre.contains('小説')) {
      ndc = '9';
    } else if (selectedGenre.contains('漫画') || selectedGenre.contains('マンガ')) {
      ndc = '726.1';
    } else if (selectedGenre.contains('ビジネス') || selectedGenre.contains('産業')) {
      ndc = '6';
    } else if (selectedGenre.contains('社会') || selectedGenre.contains('経済') ||
               selectedGenre.contains('法律')) {
      ndc = '3';
    } else if (selectedGenre.contains('科学') || selectedGenre.contains('数学') ||
               selectedGenre.contains('医学')) {
      ndc = '4';
    } else if (selectedGenre.contains('技術') || selectedGenre.contains('工学')) {
      ndc = '5';
    } else if (selectedGenre.contains('芸術') || selectedGenre.contains('スポーツ')) {
      ndc = '7';
    } else if (selectedGenre.contains('歴史') || selectedGenre.contains('地理')) {
      ndc = '2';
    } else if (selectedGenre.contains('哲学') || selectedGenre.contains('宗教')) {
      ndc = '1';
    } else if (selectedGenre.contains('言語') || selectedGenre.contains('語学')) {
      ndc = '8';
    } else {
      any = selectedGenre.isEmpty ? '本' : selectedGenre;
    }
    return search(any: any, ndc: ndc, page: page, count: count, genre: selectedGenre,
      provider: selectedGenre.contains('新着') ? 'iss-ndl-opac-inprocess' : 'iss-ndl-opac-national');
  }
}
).hasMatch(isbn)) {
      return null;
    }
    for (final provider in const [
      'iss-ndl-opac', 'iss-ndl-opac-inprocess',
    ]) {
      final candidates = await search(
        isbn: isbn, provider: provider, count: 5,
      );
      for (final item in candidates) {
        if (item.isbn == isbn) return item;
      }
    }
    return null;
  }

  static Future<List<Book>> searchBySelectedGenre({
    required String selectedGenre,
    int page = 1,
    int count = 10,
  }) {
    String? ndc;
    String? any;
    if (selectedGenre.contains('新着') || selectedGenre.contains('おすすめ')) {
      // NDL search has no Rakuten equivalent for release-date ranking.
      // Published-date sorting is performed by BookRepository.
      any = '本';
    } else if (selectedGenre.contains('English') || selectedGenre.contains('洋書')) {
      any = 'English';
    } else if (selectedGenre.contains('ベストセラー') || selectedGenre.contains('人気') ||
               selectedGenre.contains('話題')) {
      any = '本';
    } else if (selectedGenre.contains('文学') || selectedGenre.contains('小説')) {
      ndc = '9';
    } else if (selectedGenre.contains('漫画') || selectedGenre.contains('マンガ')) {
      ndc = '726.1';
    } else if (selectedGenre.contains('ビジネス') || selectedGenre.contains('産業')) {
      ndc = '6';
    } else if (selectedGenre.contains('社会') || selectedGenre.contains('経済') ||
               selectedGenre.contains('法律')) {
      ndc = '3';
    } else if (selectedGenre.contains('科学') || selectedGenre.contains('数学') ||
               selectedGenre.contains('医学')) {
      ndc = '4';
    } else if (selectedGenre.contains('技術') || selectedGenre.contains('工学')) {
      ndc = '5';
    } else if (selectedGenre.contains('芸術') || selectedGenre.contains('スポーツ')) {
      ndc = '7';
    } else if (selectedGenre.contains('歴史') || selectedGenre.contains('地理')) {
      ndc = '2';
    } else if (selectedGenre.contains('哲学') || selectedGenre.contains('宗教')) {
      ndc = '1';
    } else if (selectedGenre.contains('言語') || selectedGenre.contains('語学')) {
      ndc = '8';
    } else {
      any = selectedGenre.isEmpty ? '本' : selectedGenre;
    }
    return search(any: any, ndc: ndc, page: page, count: count, genre: selectedGenre,
      provider: selectedGenre.contains('新着') ? 'iss-ndl-opac-inprocess' : 'iss-ndl-opac-national');
  }
}
