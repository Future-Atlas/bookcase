import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rakuten_credit.dart';

/// Attribution required for NDL-created CC BY 4.0 bibliographic records.
class CatalogCredit extends StatelessWidget {
  const CatalogCredit({super.key});

  static const _sourceUrl = 'https://ndlsearch.ndl.go.jp/';
  static const _licenseUrl = 'https://creativecommons.org/licenses/by/4.0/deed.ja';
  static const _openBdUrl = 'https://openbd.jp/';
  static const _rakutenUrl = 'https://webservice.rakuten.co.jp/';
  static const _rakutenCatalog = bool.fromEnvironment(
    'RAKUTEN_CATALOG',
    defaultValue: bool.fromEnvironment(
      'STAGING_RAKUTEN_CATALOG',
      defaultValue: false,
    ),
  );
  static const _openLibraryUrl = 'https://openlibrary.org/';
  static const _googleBooksUrl = 'https://books.google.com/';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_rakutenCatalog)
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Center(child: RakutenCredit()),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(_rakutenUrl)),
                child: const Text(
                  '書籍情報・書影の一部：楽天ブックス（楽天ウェブサービス）',
                ),
              ),
            ],
          ),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            if (!_rakutenCatalog)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(_sourceUrl)),
                child: const Text('書誌情報：国立国会図書館サーチ（国立国会図書館）'),
              ),
            if (!_rakutenCatalog)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(_licenseUrl)),
                child: const Text('CC BY 4.0'),
              ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_openBdUrl)),
              child: const Text('書影等の一部：openBD'),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_openLibraryUrl)),
              child: const Text('書誌情報の一部：Open Library'),
            ),
            TextButton(
              onPressed: () => launchUrl(Uri.parse(_googleBooksUrl)),
              child: const Text('書影の一部：Google ブックス'),
            ),
          ],
        ),
      ],
    ),
  );
}
