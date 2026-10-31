import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/book.dart';

/// Enrichment is optional. Failed or missing records must never remove
/// existing user-authored reviews and bookshelf entries.
class OpenBdApi {
  static Future<List<Book>> enrich(List<Book> books) async {
    final isbnList = books.map((b) => b.isbn).where(
      (isbn) => RegExp(r'^\d{13}$').hasMatch(isbn),
    ).toSet().take(25).toList();
    if (isbnList.isEmpty) return books;
    try {
      final response = await http.get(Uri(
        path: '/api/openbd', queryParameters: {'isbn': isbnList.join(',')},
      )).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return books;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! List || data.length != isbnList.length) return books;
      final enrichment = <String, Map<String, dynamic>>{};
      for (var i = 0; i < data.length; i++) {
        if (data[i] is Map<String, dynamic>) {
          enrichment[isbnList[i]] = data[i] as Map<String, dynamic>;
        }
      }
      return books.map((book) {
        final record = enrichment[book.isbn];
        if (record == null) return book;
        final summary = record['summary'];
        final onix = record['onix'];
        final summaryData = summary is Map ? summary : const {};
        final onixData = onix is Map ? onix : const {};
        final cover = summaryData['cover']?.toString() ?? '';
        final validCover = Uri.tryParse(cover);
        final canUseCover = validCover != null &&
            validCover.scheme == 'https' && validCover.userInfo.isEmpty;
        final tags = <String>[];
        _collectAudience(onixData, tags);
        final adult = tags.any((code) =>
          code == '03' || code == '06' || code == '07');
        final description = _description(onixData);
        return book.copyWith(
          coverUrl: canUseCover ? cover : book.coverUrl,
          description: description.isNotEmpty ? description : book.description,
          adultContentFlag: adult,
          ageRatingSource: tags.isEmpty ? 'unknown' : 'openbd',
        );
      }).toList(growable: false);
    } catch (_) {
      return books;
    }
  }

  // Only the ONIX adult rating scheme (22) is considered. A general adult
  // readership code is NOT the same as explicit 18+ material.
  static void _collectAudience(Object? node, List<String> output) {
    if (node is Map) {
      if (node['AudienceCodeType']?.toString() == '22') {
        final code = node['AudienceCodeValue']?.toString() ??
            node['AudienceCode']?.toString();
        if (code != null) output.add(code.padLeft(2, '0'));
      }
      for (final value in node.values) {
        _collectAudience(value, output);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectAudience(value, output);
      }
    }
  }

  static String _description(Map onix) {
    final collateral = onix['CollateralDetail'];
    if (collateral is! Map) return '';
    final texts = collateral['TextContent'];
    final candidates = texts is List ? texts : [texts];
    for (final item in candidates) {
      if (item is Map && item['Text'] is String) {
        final value = (item['Text'] as String).replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }
}
