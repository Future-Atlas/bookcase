import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Attribution required for NDL-created CC BY 4.0 bibliographic records.
class CatalogCredit extends StatelessWidget {
  const CatalogCredit({super.key});

  static const _sourceUrl = 'https://ndlsearch.ndl.go.jp/';
  static const _licenseUrl = 'https://creativecommons.org/licenses/by/4.0/deed.ja';
  static const _openBdUrl = 'https://openbd.jp/';

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.center,
    children: [
      TextButton(
        onPressed: () => launchUrl(Uri.parse(_sourceUrl)),
        child: const Text('書誌情報：国立国会図書館サーチ（国立国会図書館）'),
      ),
      TextButton(
        onPressed: () => launchUrl(Uri.parse(_licenseUrl)),
        child: const Text('CC BY 4.0'),
      ),
      TextButton(
        onPressed: () => launchUrl(Uri.parse(_openBdUrl)),
        child: const Text('書影等の一部：openBD'),
      ),
    ],
  );
}
