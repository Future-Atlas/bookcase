import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/models/post.dart';
import 'package:sharemarium/services/post_book_metadata_resolver.dart';

Post samplePost(String id, String bookId) => Post(
  id: id,
  profileId: 'profile-1',
  bookId: bookId,
  rating: 4.0,
  comment: '感想',
  createdAt: DateTime(2026, 11, 15),
  username: 'reader',
  userAvatarUrl: '',
  bookTitle: '保存済みの本のタイトル',
  bookAuthor: '保存済みの著者',
  bookCoverUrl: '',
);

Book catalogBook(String isbn, {String coverUrl = 'https://example.com/cover.jpg'}) => Book(
  id: isbn,
  isbn: isbn,
  title: 'APIのタイトル',
  author: 'APIの著者',
  publisher: 'publisher',
  pubDate: '',
  coverUrl: coverUrl,
  coverSource: 'openbd',
);

void main() {
  test('successful covers are reused across feed loads and repeated posts', () async {
    var requests = 0;
    final resolver = PostBookMetadataResolver(
      fetcher: (id) async {
        requests++;
        return catalogBook(id);
      },
    );
    final first = await resolver.enrich([
      samplePost('1', '9784000000001'),
      samplePost('2', '9784000000001'),
    ]);
    expect(requests, 1);
    expect(first.map((post) => post.bookCoverUrl), everyElement('https://example.com/cover.jpg'));
    expect(first.first.bookTitle, '保存済みの本のタイトル');

    final next = await resolver.enrich([samplePost('3', '9784000000001')]);
    expect(requests, 1, reason: 'Returning from guide must not re-fetch a good cover');
    expect(next.single.bookCoverSource, 'openbd');
  });

  test('one transient metadata error does not discard other posts', () async {
    final resolver = PostBookMetadataResolver(
      fetcher: (id) async {
        if (id == 'unavailable') throw StateError('temporary outage');
        return catalogBook(id);
      },
    );
    final results = await resolver.enrich([
      samplePost('a', 'unavailable'),
      samplePost('b', 'available'),
    ]);
    expect(results, hasLength(2));
    expect(results.first.bookTitle, '保存済みの本のタイトル');
    expect(results.first.bookCoverUrl, isEmpty);
    expect(results.last.bookCoverUrl, isNotEmpty);
  });

  test('failed and cover-less lookups are retryable later', () async {
    var calls = 0;
    final resolver = PostBookMetadataResolver(fetcher: (id) async {
      calls++;
      if (calls == 1) return catalogBook(id, coverUrl: '');
      return catalogBook(id);
    });
    final before = await resolver.enrich([samplePost('a', '9784000000002')]);
    expect(before.single.bookCoverUrl, isEmpty);
    final after = await resolver.enrich([samplePost('a', '9784000000002')]);
    expect(after.single.bookCoverUrl, isNotEmpty);
    expect(calls, 2);
  });

  test('cache is bounded for long browsing sessions', () async {
    var calls = 0;
    final resolver = PostBookMetadataResolver(
      maxCachedBooks: 1,
      fetcher: (id) async {calls++; return catalogBook(id);},
    );
    await resolver.enrich([samplePost('a', 'one')]);
    await resolver.enrich([samplePost('b', 'two')]);
    await resolver.enrich([samplePost('c', 'one')]);
    expect(calls, 3, reason: 'Old metadata must be evicted at capacity');
  });
}
