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
  late Future<({Uri uri, int itemPrice})?> _destination;

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
        oldWidget.book.rakutenAffiliateUrl != widget.book.rakutenAffiliateUrl ||
        oldWidget.book.itemPrice != widget.book.itemPrice) {
      _destination = _resolve();
    }
  }

  Future<({Uri uri, int itemPrice})?> _resolve() async {
    final provided = RakutenBookLink.validatedDestination(
      widget.book.rakutenAffiliateUrl,
    );
    if (provided != null) {
      return (uri: provided, itemPrice: widget.book.itemPrice);
    }
    try {
      if (widget.lookup != null) {
        final uri = RakutenBookLink.validatedDestination(
          await widget.lookup!(widget.book),
        );
        return uri == null
            ? null
            : (uri: uri, itemPrice: widget.book.itemPrice);
      }

      final bookId = widget.book.isbn.isNotEmpty
          ? widget.book.isbn
          : widget.book.id;
      final resolvedBook = await RakutenApi.fetchBookById(bookId);
      final resolvedUri = RakutenBookLink.validatedDestination(
        resolvedBook?.rakutenAffiliateUrl,
      );
      if (resolvedUri != null) {
        return (
          uri: resolvedUri,
          itemPrice: resolvedBook?.itemPrice ?? widget.book.itemPrice,
        );
      }

      final fallbackUri = RakutenBookLink.validatedDestination(
        await RakutenApi.fetchAffiliateUrlForBook(widget.book),
      );
      return fallbackUri == null
          ? null
          : (uri: fallbackUri, itemPrice: widget.book.itemPrice);
    } catch (_) {
      return null;
    }
  }

  String _priceLabel(int itemPrice) {
    if (itemPrice <= 0) return '';
    final digits = itemPrice.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        output.write(',');
      }
      output.write(digits[index]);
    }
    return '（税込${output}円）';
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
  Widget build(BuildContext context) =>
      FutureBuilder<({Uri uri, int itemPrice})?>(
        future: _destination,
        builder: (context, snapshot) {
          final destination = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done ||
              destination == null) {
            return const SizedBox.shrink();
          }
          final priceLabel = _priceLabel(destination.itemPrice);
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              onPressed: () => _open(destination.uri),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text('楽天ブックスで購入する$priceLabel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFBF0000),
              ),
            ),
          );
        },
      );
}
