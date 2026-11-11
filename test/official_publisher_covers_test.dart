import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/api/official_publisher_covers.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/widgets/book_cover_image.dart';

Book example(String isbn, {String coverUrl = '', String coverSource = ''}) =>
    Book(
      id: isbn,
      isbn: isbn,
      title: '書影テスト',
      author: '著者',
      publisher: '',
      pubDate: '',
      coverUrl: coverUrl,
      coverSource: coverSource,
    );

void main() {
  test('only checksum-valid publisher-owned ISBNs resolve to official covers', () {
    expect(
      OfficialPublisherCovers.coverUrlForIsbn('9784251096883'),
      'https://www.akaneshobo.co.jp/data/book_imgs_250/9784251096883.jpg',
    );
    expect(
      OfficialPublisherCovers.coverUrlForIsbn('9784876154647'),
      'https://www.goken-net.co.jp/image//large/9784876154647.jpg',
    );
    // Different publishers and invented ISBNs must never trigger requests.
    expect(OfficialPublisherCovers.coverUrlForIsbn('9784488402327'), isNull);
    expect(OfficialPublisherCovers.coverUrlForIsbn('9784251096882'), isNull);
    expect(OfficialPublisherCovers.coverUrlForIsbn('9784876154648'), isNull);
    expect(OfficialPublisherCovers.coverUrlForIsbn('9784251096883/evil'), isNull);
    expect(OfficialPublisherCovers.coverUrlForIsbn('978-4-251-09688-3'),
        isNull);
    expect(OfficialPublisherCovers.coverUrlForIsbn(''), isNull);
  });

  test('openBD takes precedence, publisher cover is fallback only', () {
    final akane = example('9784251096883');
    final openbd = example(
      '9784251096883',
      coverUrl: 'https://cover.openbd.jp/9784251096883.jpg',
      coverSource: 'openbd',
    );
    expect(
      BookCoverImage.approvedCoverUrl(akane),
      'https://www.akaneshobo.co.jp/data/book_imgs_250/9784251096883.jpg',
    );
    expect(BookCoverImage.approvedCoverUrl(openbd), openbd.coverUrl);
    expect(BookCoverImage.isApprovedCover(akane), isTrue);
    expect(BookCoverImage.webImageStrategyForBook(akane),
        WebHtmlElementStrategy.prefer);
  });

  test('unlicensed stored cover never leaks to its old provider', () {
    final google = example(
      '9784876154647',
      coverUrl: 'https://books.google.com/books/content?id=old',
      coverSource: 'google_books',
    );
    expect(
      BookCoverImage.approvedCoverUrl(google),
      'https://www.goken-net.co.jp/image//large/9784876154647.jpg',
    );
    final unapproved = example(
      '9784488402327',
      coverUrl: 'https://books.google.com/books/content?id=old',
      coverSource: 'google_books',
    );
    expect(BookCoverImage.approvedCoverUrl(unapproved), isNull);
    expect(BookCoverImage.webImageStrategyForBook(unapproved),
        WebHtmlElementStrategy.never);
  });

  testWidgets('publisher covers preserve the entire original image',
      (tester) async {
    final publisherBook = example('9784251096883');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 138,
          height: 202,
          child: BookCoverImage(book: publisherBook),
        ),
      ),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    expect((image.image as NetworkImage).url,
        BookCoverImage.approvedCoverUrl(publisherBook));
  });
}
