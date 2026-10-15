import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/rakuten_api.dart';
import '../models/book.dart';

class RakutenBookLink extends StatefulWidget {
  const RakutenBookLink({super.key, required this.book, this.lookup});
  final Book book;
  final Future<String?> Function(Book)? lookup;

  static Uri? validatedDestination(String? value) {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'hb.afl.rakuten.co.jp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        !uri.path.startsWith('/hgc/')) {
      return null;
    }
    final product = Uri.tryParse(uri.queryParameters['pc'] ?? '');
    if (product == null ||
        product.scheme != 'https' ||
        product.host != 'books.rakuten.co.jp' ||
        product.userInfo.isNotEmpty ||
        product.hasPort ||
        !RegExp(r'^/rb/\d+/?$').hasMatch(product.path)) {
      return null;
    }
    return uri;
  }

  @override
  State<RakutenBookLink> createState() => _RakutenBookLinkState();
}

class _RakutenBookLinkState extends State<RakutenBookLink> {
  late Future<Uri?> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _resolve();
  }

  @override
  void didUpdateWidget(covariant RakutenBookLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id ||
        oldWidget.book.isbn != widget.book.isbn ||
        oldWidget.book.rakutenAffiliateUrl != widget.book.rakutenAffiliateUrl) {
      _destination = _resolve();
    }
  }

  Future<Uri?> _resolve() async {
    final provided = RakutenBookLink.validatedDestination(
      widget.book.rakutenAffiliateUrl,
    );
    if (provided != null) return provided;
    try {
      final url = await (widget.lookup ?? RakutenApi.fetchAffiliateUrlForBook)(
        widget.book,
      );
      return RakutenBookLink.validatedDestination(url);
    } catch (_) {
      return null;
    }
  }

  Future<void> _open(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('楽天ブックスを開けませんでした。')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uri?>(
    future: _destination,
    builder: (context, snapshot) {
      final uri = snapshot.data;
      if (snapshot.connectionState != ConnectionState.done || uri == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => _open(uri),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('楽天ブックスで購入する'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBF0000),
                backgroundColor: const Color(0xFF2E8B57),
                side: const BorderSide(color: Color(0xFFBF0000)),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '広告・楽天アフィリエイトリンク',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black87, fontSize: 12),
            ),
            const Text(
              'このリンク経由の購入により、Sharemariumに報酬が入る場合があります。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ],
        ),
      );
    },
  );
}
