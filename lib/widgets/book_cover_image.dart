import 'package:flutter/material.dart';

import '../models/book.dart';

/// Only show cover art with a documented right to use it for book
/// introduction/promotion. openBD permits this use by companies, subject
/// to its terms: https://openbd.jp/terms/
///
/// Google Books, Open Library and legacy retailer URLs are intentionally not
/// automatic image sources. A URL reachable on the internet is not a license.
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({
    super.key,
    required this.book,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final Book book;
  final BoxFit fit;
  final double? width;
  final double? height;

  static bool isSafeRemoteCover(String url) {
    final parsed = Uri.tryParse(url.trim());
    return parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty &&
        parsed.userInfo.isEmpty &&
        !parsed.hasPort;
  }

  /// The source tag is assigned only by OpenBdApi.enrichRecord. For old
  /// persisted post data without a source tag, allow just the official
  /// openBD image host; never infer rights for arbitrary publisher/CDN URLs.
  static bool isApprovedCover(Book book) {
    if (!isSafeRemoteCover(book.coverUrl)) return false;
    if (book.coverSource.isNotEmpty && book.coverSource != 'openbd') {
      return false;
    }
    final host = Uri.parse(book.coverUrl.trim()).host.toLowerCase();
    const excluded = {
      'books.google.com',
      'books.googleusercontent.com',
      'covers.openlibrary.org',
      'images.weserv.nl',
      'thumbnail.image.rakuten.co.jp',
      'image.rakuten.co.jp',
    };
    if (excluded.contains(host)) return false;
    if (book.coverSource == 'openbd') return true;
    return host == 'cover.openbd.jp';
  }

  /// Covers returned by openBD may reside on publishers' own HTTPS hosts.
  /// HTML-first rendering avoids speculative CORS-blocked XHRs in Flutter Web.
  static WebHtmlElementStrategy webImageStrategyForBook(Book book) =>
      isApprovedCover(book)
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never;

  Widget _placeholder(BuildContext context) => Container(
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF32353A)
        : const Color(0xFFE9E5DD),
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, color: Colors.grey, size: 28),
          if (constraints.maxHeight >= 90) ...[
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                book.title,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '表紙画像なし',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.grey,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    ),
  );


  @override
  Widget build(BuildContext context) {
    if (!isApprovedCover(book)) return _placeholder(context);
    return Image.network(
      book.coverUrl.trim(),
      fit: fit,
      width: width,
      height: height,
      semanticLabel: '${book.title}の表紙',
      webHtmlElementStrategy: webImageStrategyForBook(book),
      errorBuilder: (_, error, stackTrace) => _placeholder(context),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF32353A)
              : const Color(0xFFE7E7E7),
          child: const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}
