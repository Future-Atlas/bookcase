import 'package:flutter/material.dart';

import '../models/book.dart';
import '../api/official_publisher_covers.dart';

/// Render book-introduction covers supplied by the active catalog API, openBD,
/// or a verified publisher site. Provider URLs require matching provenance.
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({
    super.key,
    required this.book,
    this.width,
    this.height,
  });

  final Book book;
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

  /// Prefer a provenance-verified catalog image. If missing or unapproved,
  /// use only the publisher's own deterministic ISBN-specific cover URL.
  static String? approvedCoverUrl(Book book) {
    final candidate = book.coverUrl.trim();
    if (isSafeRemoteCover(candidate) &&
        (book.coverSource.isEmpty ||
            book.coverSource == 'openbd' ||
            book.coverSource == 'rakuten')) {
      final host = Uri.parse(candidate).host.toLowerCase();
      const excluded = {
        'books.google.com',
        'books.googleusercontent.com',
        'covers.openlibrary.org',
        'images.weserv.nl',
        'thumbnail.image.rakuten.co.jp',
        'image.rakuten.co.jp',
      };
      final approvedRakuten = book.coverSource == 'rakuten' &&
          const {
            'thumbnail.image.rakuten.co.jp',
            'image.rakuten.co.jp',
          }.contains(host);
      if (approvedRakuten ||
          (!excluded.contains(host) &&
              (book.coverSource == 'openbd' || host == 'cover.openbd.jp'))) {
        return candidate;
      }
    }
    return OfficialPublisherCovers.coverUrlForIsbn(book.isbn.trim());
  }

  static bool isApprovedCover(Book book) => approvedCoverUrl(book) != null;

  /// Covers returned by openBD may reside on publishers' own HTTPS hosts.
  /// HTML-first rendering avoids speculative CORS-blocked XHRs in Flutter Web.
  static WebHtmlElementStrategy webImageStrategyForBook(Book book) =>
      isApprovedCover(book)
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never;

  Widget _placeholder(BuildContext context) => Container(
    width: width,
    height: height,
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
    final approvedUrl = approvedCoverUrl(book);
    if (approvedUrl == null) return _placeholder(context);
    return Image.network(
      approvedUrl,
      // Neither publisher permits arbitrarily cropping its original artwork.
      // Keep the entire jacket visible, regardless of surrounding card shape.
      fit: BoxFit.contain,
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
