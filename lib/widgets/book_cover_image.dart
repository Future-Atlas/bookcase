import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';

/// Prefer a catalog cover, then the edition-specific Open Library cover.
/// The Open Library endpoint uses default=false to avoid false blank images.
/// Flutter Web CanvasKit must use HTML-first rendering on known cover CDNs
/// that do not provide the cross-origin headers required for byte fetching.
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

  /// Prevent needless Flutter Web XMLHttpRequests that known book-cover CDNs
  /// will reject due to missing CORS response headers. An HTML <img> can
  /// display these public URLs without reading their response bytes in JS.
  /// This affects only Web; native clients still use decoded image bytes.
  /// Exact host checks prevent pretending an arbitrary URL is a known CDN.
  static WebHtmlElementStrategy webImageStrategyForUrl(String url) {
    final parsed = Uri.tryParse(url.trim());
    const htmlFirstHosts = {
      'cover.openbd.jp',
      'books.google.com',
      'books.googleusercontent.com',
      'covers.openlibrary.org',
    };
    if (parsed != null && parsed.scheme == 'https' &&
        parsed.userInfo.isEmpty && !parsed.hasPort &&
        htmlFirstHosts.contains(parsed.host.toLowerCase())) {
      return WebHtmlElementStrategy.prefer;
    }
    return WebHtmlElementStrategy.fallback;
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
    bool showGoogleCredit = false,
  }) {
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      semanticLabel: book.title + 'の表紙',
      // Attach credit to a successfully painted Google image, not to the
      // fallback result. This also avoids labeling an Open Library image as
      // Google Books when the primary thumbnail fails.
      frameBuilder: showGoogleCredit
          ? (context, image, frame, _) =>
              frame == null ? image : _withSourceCredit(image)
          : null,
      // Official cover CDNs do not consistently supply CORS headers.
      // HTML-first avoids a guaranteed failed XHR before drawing the image.
      webHtmlElementStrategy: webImageStrategyForUrl(url),
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

  /// Google Books requires a visible attribution link alongside thumbnails.
  /// The responsive badge stays clickable even in small profile grids.
  Widget _withSourceCredit(Widget image) {
    if (book.coverSource != 'google_books') return image;
    final url = Uri.tryParse(book.coverAttributionUrl);
    if (url == null || url.scheme != 'https' ||
        url.host != 'books.google.com' || url.userInfo.isNotEmpty) {
      return image;
    }
    return LayoutBuilder(builder: (context, constraints) {
      final tiny = constraints.maxWidth.isFinite &&
          constraints.maxWidth < 90;
      return Stack(
        fit: StackFit.expand,
        children: [
          image,
          Positioned(
            top: 3, right: 3,
            child: Tooltip(
              message: '表紙画像の情報：Google ブックス',
              child: GestureDetector(
                onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xCC222222),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3, vertical: 2,
                  ),
                  child: Text(
                    tiny ? 'Google' : 'Google ブックス',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = book.coverUrl.trim();
    final fallback = openLibraryCoverUrl(book.isbn);
    if (isSafeRemoteCover(primary)) {
      return _network(
        context,
        primary,
        showGoogleCredit: book.coverSource == 'google_books',
        onError: () {
          if (fallback == null || primary == fallback) {
            return _placeholder(context);
          }
          return _network(
            context, fallback,
            onError: () => _placeholder(context),
          );
        },
      );
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
