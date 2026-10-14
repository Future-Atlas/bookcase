// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class RakutenCredit extends StatelessWidget {
  const RakutenCredit({super.key});

  static bool _registered = false;
  static const _viewType = 'sharemarium-rakuten-credit';
  // Official attribution markup. Never interpolate user content here.
  static const _markup = '''
<!-- Rakuten Web Services Attribution Snippet FROM HERE -->
<a href="https://webservice.rakuten.co.jp/" target="_blank"><img src="https://webservice.rakuten.co.jp/img/credit/200709/credit_22121.gif" border="0" alt="Rakuten Web Service Center" title="Rakuten Web Service Center" width="221" height="21"/></a>
<!-- Rakuten Web Services Attribution Snippet TO HERE -->
''';

  @override
  Widget build(BuildContext context) {
    if (!_registered) {
      ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        return html.DivElement()..setInnerHtml(
          _markup,
          treeSanitizer: html.NodeTreeSanitizer.trusted,
        );
      });
      _registered = true;
    }
    return const SizedBox(
      width: 221,
      height: 21,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
