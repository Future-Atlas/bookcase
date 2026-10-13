import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RakutenCredit extends StatelessWidget {
  const RakutenCredit({super.key});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => launchUrl(Uri.parse('https://webservice.rakuten.co.jp/')),
    child: Image.network(
      'https://webservice.rakuten.co.jp/img/credit/200709/credit_22121.gif',
      width: 221,
      height: 21,
      semanticLabel: 'Rakuten Web Service Center',
      errorBuilder: (context, error, stackTrace) => const SizedBox(
        width: 221,
        height: 21,
        child: Text('Rakuten Web Service Center'),
      ),
    ),
  );
}
