import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/book.dart';

/// Optional, short-lived enrichment by openBD. The user-owned bookshelf and
/// reviews must stay available when records or covers are absent/withdrawn.
class OpenBdApi {
  static const batchSize = 25;

  static Future<List<Book>> enrich(List<Book> books) async {
    final isbnList = books.map((b) => b.isbn)
        .where((isbn) => RegExp(r'^[0-9]{13}$').hasMatch(isbn))
        .toSet().toList(growable: false);
    if (isbnList.isEmpty) return books;
    final byIsbn = <String, Map<String, dynamic>>{};
    for (var start = 0; start < isbnList.length; start += batchSize) {
      final chunk = isbnList.skip(start).take(batchSize).toList();
      try {
        final response = await http.get(Uri(
          path: '/api/openbd',
          queryParameters: {'isbn': chunk.join(',')},
        )).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data is! List || data.length != chunk.length) continue;
        for (var i = 0; i < chunk.length; i++) {
          if (data[i] is Map<String, dynamic>) {
            final record = data[i] as Map<String, dynamic>;
            final summary = record['summary'];
            if (summary is Map && summary['isbn'] != null &&
                summary['isbn'].toString() != chunk[i]) {
              // A record mismatched to its requested ISBN must not be applied.
              continue;
            }
            byIsbn[chunk[i]] = record;
          }
        }
      } catch (_) {
        // Enrichment is optional: preserve the unaffected ISBNs.
      }
    }
    return books.map((book) {
      final record = byIsbn[book.isbn];
      return record == null ? book : enrichRecord(book, record);
    }).toList(growable: false);
  }

  /// Pure transform to support fixture tests for ONIX safety classifications.
  static Book enrichRecord(Book book, Map<String, dynamic> record) {
    final summary = record['summary'];
    final onix = record['onix'];
    final summaryData = summary is Map ? summary : const {};
    final onixData = onix is Map ? onix : const {};
    final cover = summaryData['cover']?.toString().trim() ?? '';
    final parsedCover = Uri.tryParse(cover);
    final validCover = parsedCover != null &&
        parsedCover.scheme == 'https' &&
        parsedCover.host.isNotEmpty && parsedCover.userInfo.isEmpty;
    final codes = <String>[];
    _collectAdultAudienceCodes(onixData, codes);
    // ONIX list 203 (adult audience rating). 06 (language) and
    // 07 (intolerance) are content warnings, NOT proof of a legal 18+ rating.
    // Likewise 04 (violence), 05 (drugs) alone do not establish 18+.
    // 01 = adult audience; 02 = adult content warning; 03 = sexual content.
    const restrictedCodes = {'01', '02', '03'};
    final explicitlyAdult = codes.any(restrictedCodes.contains);
    final description = _description(onixData);
    return book.copyWith(
      coverUrl: validCover ? cover : book.coverUrl,
      description: description.isNotEmpty ? description : book.description,
      adultContentFlag: book.adultContentFlag || explicitlyAdult,
      ageRatingSource: codes.isEmpty ? book.ageRatingSource : 'openbd',
    );
  }

  static void _collectAdultAudienceCodes(Object? node, List<String> output) {
    if (node is Map) {
      if (node['AudienceCodeType']?.toString() == '22') {
        final value = node['AudienceCodeValue']?.toString() ??
            node['AudienceCode']?.toString();
        if (value != null && RegExp(r'^[0-9]{1,2}$').hasMatch(value)) {
          output.add(value.padLeft(2, '0'));
        }
      }
      for (final value in node.values) {
        _collectAdultAudienceCodes(value, output);
      }
    } else if (node is List) {
      for (final value in node) {
        _collectAdultAudienceCodes(value, output);
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
        final value = (item['Text'] as String)
            .replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }
}
