import '../api/book_catalog_lookup.dart';
import '../models/book.dart';
import '../models/post.dart';

typedef PostBookFetcher = Future<Book?> Function(String bookId);

/// A session-local cache of successful, ISBN-specific catalog cover lookups.
/// It avoids refetching every post's cover when navigating or reopening feeds.
/// Failures and cover-less records are NOT cached, allowing later retries.
class PostBookMetadataResolver {
  PostBookMetadataResolver({
    PostBookFetcher? fetcher,
    this.maxCachedBooks = 200,
  }) : _fetcher = fetcher ?? const BookCatalogLookup().fetchById;

  final PostBookFetcher _fetcher;
  final int maxCachedBooks;
  final Map<String, Book> _coverCache = <String, Book>{};

  Future<List<Post>> enrich(List<Post> posts) async {
    if (posts.isEmpty) return posts;

    // A book may appear in many posts. Look it up only once per batch, in
    // addition to reusing successful covers from previous feed loads.
    final resolvedById = <String, Book?>{};
    for (final post in posts) {
      final id = post.bookId.trim();
      if (id.isEmpty || resolvedById.containsKey(id)) continue;
      final cached = _coverCache[id];
      if (cached != null) {
        resolvedById[id] = cached;
        continue;
      }
      try {
        final book = await _fetcher(id);
        resolvedById[id] = book;
        if (book != null && book.coverUrl.trim().isNotEmpty &&
            maxCachedBooks > 0) {
          // Maintain a bounded cache and avoid retaining responses without
          // usable cover metadata (which should be retried on future loads).
          if (_coverCache.length >= maxCachedBooks) {
            _coverCache.remove(_coverCache.keys.first);
          }
          _coverCache[id] = book;
        }
      } catch (_) {
        // One transient catalog error must not erase the entire post feed.
        resolvedById[id] = null;
      }
    }

    return posts.map((post) {
      final book = resolvedById[post.bookId.trim()];
      if (book == null) return post;
      return post.copyWith(
        bookTitle: post.bookTitle.trim().isNotEmpty
            ? post.bookTitle
            : book.title,
        bookAuthor: post.bookAuthor.trim().isNotEmpty
            ? post.bookAuthor
            : book.author,
        bookCoverUrl: book.coverUrl.trim().isNotEmpty
            ? book.coverUrl
            : post.bookCoverUrl,
        bookCoverSource: book.coverUrl.trim().isNotEmpty
            ? book.coverSource
            : post.bookCoverSource,
      );
    }).toList(growable: false);
  }
}
