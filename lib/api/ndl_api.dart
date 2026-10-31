import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/book.dart';

/// One raw NDL OpenSearch window and its pagination information.
/// Raw item counts matter: some NDL records do not carry an ISBN, but still
/// occupy slots in the upstream result page.
class NdlSearchBatch {
  const NdlSearchBatch({
    required this.books,
    required this.rawCount,
    required this.hasMore,
  });

  final List<Book> books;
  final int rawCount;
  final bool hasMore;
}

class NdlApi {
  static const _base = '/api/ndl';
  static const national = 'iss-ndl-opac-national';
  static const inProcess = 'iss-ndl-opac-inprocess';
  static const holdings = 'iss-ndl-opac';
  // NDL's Japan-related foreign-language bibliography (CC BY metadata).
  static const foreignBibliography = 'ndl-boj';

  static Uri searchUri({
    String? any,
    String? title,
    String? creator,
    String? publisher,
    String? isbn,
    String? ndc,
    String? from,
    String? until,
    String provider = national,
    int start = 1,
    int count = 20,
  }) => Uri(path: _base, queryParameters: {
    'dpid': provider,
    'idx': start.toString(),
    'cnt': count.toString(),
    'mediatype': 'books',
    if (any != null && any.isNotEmpty) 'any': any,
    if (title != null && title.isNotEmpty) 'title': title,
    if (creator != null && creator.isNotEmpty) 'creator': creator,
    if (publisher != null && publisher.isNotEmpty) 'publisher': publisher,
    if (isbn != null && isbn.isNotEmpty) 'isbn': isbn,
    if (ndc != null && ndc.isNotEmpty) 'ndc': ndc,
    if (from != null && from.isNotEmpty) 'from': from,
    if (until != null && until.isNotEmpty) 'until': until,
  });

  static Future<NdlSearchBatch> searchPage({
    String? any,
    String? title,
    String? creator,
    String? publisher,
    String? isbn,
    String? ndc,
    String? from,
    String? until,
    String provider = national,
    int start = 1,
    int count = 20,
    String genre = '',
  }) async {
    if (start < 1 || count < 1 || count > 50 || start + count > 501) {
      return const NdlSearchBatch(books: [], rawCount: 0, hasMore: false);
    }
    try {
      final response = await http.get(searchUri(
        any: any, title: title, creator: creator, publisher: publisher,
        isbn: isbn, ndc: ndc, from: from, until: until,
        provider: provider, start: start, count: count,
      )).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return const NdlSearchBatch(books: [], rawCount: 0, hasMore: false);
      }
      return parseSearchPage(utf8.decode(response.bodyBytes),
          start: start, count: count, genre: genre);
    } catch (_) {
      // Do not display unverified or fallback data on an upstream failure.
      return const NdlSearchBatch(books: [], rawCount: 0, hasMore: false);
    }
  }

  static Future<List<Book>> search({
    String? any,
    String? title,
    String? creator,
    String? publisher,
    String? isbn,
    String? ndc,
    String? from,
    String? until,
    String provider = national,
    int page = 1,
    int count = 20,
    String genre = '',
  }) async {
    final batch = await searchPage(
      any: any, title: title, creator: creator, publisher: publisher,
      isbn: isbn, ndc: ndc, from: from, until: until, provider: provider,
      start: (page - 1) * count + 1, count: count, genre: genre,
    );
    return batch.books;
  }

  static String? _value(XmlElement item, String name) {
    for (final element in item.children.whereType<XmlElement>()) {
      if (element.name.local == name) {
        final value = element.innerText.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String _type(XmlElement element) {
    for (final attr in element.attributes) {
      if (attr.name.local == 'type') return attr.value.toLowerCase();
    }
    return '';
  }

  static String _isbn(XmlElement item) {
    final identifiers = item.descendants.whereType<XmlElement>()
        .where((node) => node.name.local == 'identifier').toList();
    // Prefer an identifier explicitly typed as ISBN over arbitrary numeric IDs.
    identifiers.sort((a, b) {
      final ai = _type(a).contains('isbn') ? 0 : 1;
      final bi = _type(b).contains('isbn') ? 0 : 1;
      return ai.compareTo(bi);
    });
    for (final element in identifiers) {
      final value = element.innerText.trim();
      final typed = _type(element).contains('isbn') ||
          value.toLowerCase().contains('isbn');
      final match = RegExp(r'(?:^|[^0-9])((?:97[89][0-9]{10}|[0-9]{9}[0-9Xx]))(?:$|[^0-9])')
          .firstMatch(value);
      if (match != null && (typed || RegExp(r'^(?:[0-9]{13}|[0-9]{9}[0-9Xx])$').hasMatch(value))) {
        return match.group(1)!.toUpperCase();
      }
    }
    return '';
  }

  /// NDL RSS can include multiple language elements for bilingual editions.
  static String _languages(XmlElement item) {
    final values = <String>{};
    for (final element in item.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'language') continue;
      final text = element.innerText.trim().toLowerCase();
      if (text.isNotEmpty) values.add(text);
    }
    return values.join(' ');
  }

  /// A genre named 洋書 means foreign-language books, not books whose title
  /// contains the word "English". Unknown language is not guessed from cover
  /// art, title typography or Japanese/foreign publisher names.
  static bool isForeignLanguage(Book book) {
    final language = book.languageCode.trim().toLowerCase();
    if (language.isEmpty) return false;
    final codes = language.split(RegExp(r'[\s,;|/]+'));
    const notForeign = {
      'ja', 'jpn', 'japanese', '日本語', 'und',
      'unknown', 'mul', 'zxx', 'none',
    };
    const languageNames = {
      'english', 'french', 'german', 'spanish', 'chinese',
      'korean', 'russian', 'italian', 'portuguese',
      '英語', 'フランス語', 'ドイツ語', 'スペイン語', '中国語',
      '韓国語', 'ロシア語', 'イタリア語',
    };
    return codes.any((part) =>
      !notForeign.contains(part) &&
      (RegExp(r'^[a-z]{2,3}(?:-[a-z]{2,4})?
    for (final element in item.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'subject' || !_type(element).contains('ndc')) continue;
      final value = element.innerText.trim();
      if (RegExp(r'^[0-9]{1,3}(?:\.[0-9]+)?$').hasMatch(value)) return value;
    }
    return '';
  }

  static NdlSearchBatch parseSearchPage(String xml, {
    int start = 1,
    int count = 20,
    String genre = '',
  }) {
    final document = XmlDocument.parse(xml);
    final items = document.findAllElements('item').toList(growable: false);
    final result = <Book>[];
    final seen = <String>{};
    for (final item in items) {
      final title = _value(item, 'title') ?? '';
      final isbn = _isbn(item);
      if (title.isEmpty || isbn.isEmpty || !seen.add(isbn)) continue;
      result.add(Book(
        id: isbn,
        isbn: isbn,
        title: title,
        author: _value(item, 'creator') ?? _value(item, 'author') ?? '',
        publisher: _value(item, 'publisher') ?? '',
        pubDate: _value(item, 'issued') ?? _value(item, 'date') ?? '',
        coverUrl: '',
        genre: genre,
        description: _value(item, 'description') ?? '',
        languageCode: _languages(item),
        ndcCode: _ndc(item),
        catalogSource: 'ndl',
        catalogFetchedAt: DateTime.now().toUtc(),
      ));
    }
    int? total;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'totalResults') {
        total = int.tryParse(element.innerText.trim());
        break;
      }
    }
    final hasMore = total != null
        ? start + items.length - 1 < total && items.isNotEmpty
        : items.length == count;
    return NdlSearchBatch(
      books: result,
      rawCount: items.length,
      hasMore: hasMore && start + items.length <= 500,
    );
  }

  static List<Book> parseBooks(String xml, {String genre = ''}) =>
      parseSearchPage(xml, genre: genre).books;

  static Future<Book?> fetchBookById(String id) async {
    final isbn = id.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (!RegExp(r'^(?:[0-9]{13}|[0-9]{9}[0-9X])$').hasMatch(isbn)) {
      return null;
    }
    for (final provider in const [inProcess, national, holdings]) {
      final candidates = await search(isbn: isbn, provider: provider, count: 5);
      for (final item in candidates) {
        if (item.isbn == isbn) return item;
      }
    }
    return null;
  }

  /// The same public section labels as before. NDC is a prefix match and does
  /// not have the same classification boundaries as Rakuten Books genres.
  static Future<List<Book>> searchBySelectedGenre({
    required String selectedGenre,
    int page = 1,
    int count = 10,
  }) async {
    String? ndc;
    String? any;
    String? from;
    var provider = national;
    if (selectedGenre.contains('新着')) {
      provider = inProcess;
      from = DateTime.now().subtract(const Duration(days: 365))
          .toIso8601String().substring(0, 10);
    } else if (selectedGenre.contains('English') ||
        selectedGenre.contains('洋書')) {
      provider = holdings;
      // The OpenSearch interface has no verified language-only selector.
      // Restrict to records that explicitly say 'eng'/'en' below instead of
      // showing Japanese books merely mentioning the word "English".
      any = 'English';
    } else if (selectedGenre.contains('文学') ||
        selectedGenre.contains('小説')) {
      ndc = '9';
    } else if (selectedGenre.contains('漫画') ||
        selectedGenre.contains('マンガ')) {
      ndc = '726.1';
    } else if (selectedGenre.contains('ビジネス') ||
        selectedGenre.contains('産業')) {
      ndc = '6';
    } else if (selectedGenre.contains('社会') ||
        selectedGenre.contains('経済') ||
        selectedGenre.contains('法律')) {
      ndc = '3';
    } else if (selectedGenre.contains('科学') ||
        selectedGenre.contains('数学') ||
        selectedGenre.contains('医学')) {
      ndc = '4';
    } else if (selectedGenre.contains('技術') ||
        selectedGenre.contains('工学')) {
      ndc = '5';
    } else if (selectedGenre.contains('芸術') ||
        selectedGenre.contains('スポーツ')) {
      ndc = '7';
    } else if (selectedGenre.contains('歴史') ||
        selectedGenre.contains('地理')) {
      ndc = '2';
    } else if (selectedGenre.contains('哲学') ||
        selectedGenre.contains('宗教')) {
      ndc = '1';
    } else if (selectedGenre.contains('言語') ||
        selectedGenre.contains('語学')) {
      ndc = '8';
    } else {
      any = selectedGenre.isEmpty ? '本' : selectedGenre;
    }
    final matches = await search(
      any: any, ndc: ndc, from: from, provider: provider,
      page: page, count: count, genre: selectedGenre,
    );
    if (selectedGenre.contains('English') ||
        selectedGenre.contains('洋書')) {
      return matches.where((book) {
        final lang = book.languageCode.toLowerCase();
        return lang == 'eng' || lang == 'en' || lang == 'english';
      }).toList(growable: false);
    }
    return matches;
  }
}
).hasMatch(part) ||
       languageNames.contains(part)));
  }

  static String _ndc(XmlElement item) {
    for (final element in item.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'subject' || !_type(element).contains('ndc')) continue;
      final value = element.innerText.trim();
      if (RegExp(r'^[0-9]{1,3}(?:\.[0-9]+)?$').hasMatch(value)) return value;
    }
    return '';
  }

  static NdlSearchBatch parseSearchPage(String xml, {
    int start = 1,
    int count = 20,
    String genre = '',
  }) {
    final document = XmlDocument.parse(xml);
    final items = document.findAllElements('item').toList(growable: false);
    final result = <Book>[];
    final seen = <String>{};
    for (final item in items) {
      final title = _value(item, 'title') ?? '';
      final isbn = _isbn(item);
      if (title.isEmpty || isbn.isEmpty || !seen.add(isbn)) continue;
      result.add(Book(
        id: isbn,
        isbn: isbn,
        title: title,
        author: _value(item, 'creator') ?? _value(item, 'author') ?? '',
        publisher: _value(item, 'publisher') ?? '',
        pubDate: _value(item, 'issued') ?? _value(item, 'date') ?? '',
        coverUrl: '',
        genre: genre,
        description: _value(item, 'description') ?? '',
        languageCode: (_value(item, 'language') ?? '').toLowerCase(),
        ndcCode: _ndc(item),
        catalogSource: 'ndl',
        catalogFetchedAt: DateTime.now().toUtc(),
      ));
    }
    int? total;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'totalResults') {
        total = int.tryParse(element.innerText.trim());
        break;
      }
    }
    final hasMore = total != null
        ? start + items.length - 1 < total && items.isNotEmpty
        : items.length == count;
    return NdlSearchBatch(
      books: result,
      rawCount: items.length,
      hasMore: hasMore && start + items.length <= 500,
    );
  }

  static List<Book> parseBooks(String xml, {String genre = ''}) =>
      parseSearchPage(xml, genre: genre).books;

  static Future<Book?> fetchBookById(String id) async {
    final isbn = id.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (!RegExp(r'^(?:[0-9]{13}|[0-9]{9}[0-9X])$').hasMatch(isbn)) {
      return null;
    }
    for (final provider in const [inProcess, national, holdings]) {
      final candidates = await search(isbn: isbn, provider: provider, count: 5);
      for (final item in candidates) {
        if (item.isbn == isbn) return item;
      }
    }
    return null;
  }

  /// The same public section labels as before. NDC is a prefix match and does
  /// not have the same classification boundaries as Rakuten Books genres.
  static Future<List<Book>> searchBySelectedGenre({
    required String selectedGenre,
    int page = 1,
    int count = 10,
  }) async {
    String? ndc;
    String? any;
    String? from;
    var provider = national;
    if (selectedGenre.contains('新着')) {
      provider = inProcess;
      from = DateTime.now().subtract(const Duration(days: 365))
          .toIso8601String().substring(0, 10);
    } else if (selectedGenre.contains('English') ||
        selectedGenre.contains('洋書')) {
      provider = holdings;
      // The OpenSearch interface has no verified language-only selector.
      // Restrict to records that explicitly say 'eng'/'en' below instead of
      // showing Japanese books merely mentioning the word "English".
      any = 'English';
    } else if (selectedGenre.contains('文学') ||
        selectedGenre.contains('小説')) {
      ndc = '9';
    } else if (selectedGenre.contains('漫画') ||
        selectedGenre.contains('マンガ')) {
      ndc = '726.1';
    } else if (selectedGenre.contains('ビジネス') ||
        selectedGenre.contains('産業')) {
      ndc = '6';
    } else if (selectedGenre.contains('社会') ||
        selectedGenre.contains('経済') ||
        selectedGenre.contains('法律')) {
      ndc = '3';
    } else if (selectedGenre.contains('科学') ||
        selectedGenre.contains('数学') ||
        selectedGenre.contains('医学')) {
      ndc = '4';
    } else if (selectedGenre.contains('技術') ||
        selectedGenre.contains('工学')) {
      ndc = '5';
    } else if (selectedGenre.contains('芸術') ||
        selectedGenre.contains('スポーツ')) {
      ndc = '7';
    } else if (selectedGenre.contains('歴史') ||
        selectedGenre.contains('地理')) {
      ndc = '2';
    } else if (selectedGenre.contains('哲学') ||
        selectedGenre.contains('宗教')) {
      ndc = '1';
    } else if (selectedGenre.contains('言語') ||
        selectedGenre.contains('語学')) {
      ndc = '8';
    } else {
      any = selectedGenre.isEmpty ? '本' : selectedGenre;
    }
    final matches = await search(
      any: any, ndc: ndc, from: from, provider: provider,
      page: page, count: count, genre: selectedGenre,
    );
    if (selectedGenre.contains('English') ||
        selectedGenre.contains('洋書')) {
      return matches.where((book) {
        final lang = book.languageCode.toLowerCase();
        return lang == 'eng' || lang == 'en' || lang == 'english';
      }).toList(growable: false);
    }
    return matches;
  }
}
