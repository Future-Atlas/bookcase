import 'package:flutter/material.dart';

import '../models/book.dart';

/// Prefer a catalog cover, then the edition-specific Open Library cover.
/// The Open Library endpoint uses default=false to avoid false blank images.
/// Flutter Web CanvasKit needs an HTML image fallback for CDNs without CORS.
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

  static String? openLibraryCoverUrl(String isbn) {
    final normalized = isbn.trim().replaceAll(
      RegExp(r'[\s\u3000\-‐‑‒–—―−]'), '',
    ).toUpperCase();
    if (!RegExp(r'^(?:97[89]\d{10}|\d{9}[\dX])$')
        .hasMatch(normalized)) {
      return null;
    }
    return 'https://covers.openlibrary.org/b/isbn/'
        '$normalized-M.jpg?default=false';
  }

  static bool isSafeRemoteCover(String url) {
    final parsed = Uri.tryParse(url.trim());
    return parsed != null &&
        parsed.scheme == 'https' &&
        parsed.host.isNotEmpty &&
        parsed.userInfo.isEmpty;
  }

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

  Widget _network(
    BuildContext context,
    String url, {
    required Widget Function() onError,
  }) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      semanticLabel: book.title + 'の表紙',
      // Open Library serves public image URLs directly. Prefer <img> for
      // cross-origin covers to avoid a failed CORS fetch plus a second GET.
      webHtmlElementStrategy: url.startsWith(
        'https://covers.openlibrary.org/',
      ) ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.fallback,
      errorBuilder: (_, error, stackTrace) => onError(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF32353A)
              : const Color(0xFFE7E7E7),
          child: const Center(
            child: SizedBox(
              height: 20, width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = book.coverUrl.trim();
    final fallback = openLibraryCoverUrl(book.isbn);
    if (isSafeRemoteCover(primary)) {
      return _network(context, primary, onError: () {
        if (fallback == null || primary == fallback) {
          return _placeholder(context);
        }
        return _network(
          context, fallback,
          onError: () => _placeholder(context),
        );
      });
    }
    if (fallback != null) {
      return _network(
        context, fallback,
        onError: () => _placeholder(context),
      );
    }
    return _placeholder(context);
  }
}
