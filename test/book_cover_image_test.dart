import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/widgets/book_cover_image.dart';

const sample = Book(
  id: '9784488402327',
  isbn: '9784488402327',
  title: '亜愛一郎の狼狽',
  author: '泡坂妻夫',
  publisher: '東京創元社',
  pubDate: '2026.10',
  coverUrl: '',
);

void main() {
  test('openBD source can provide its own CDN or an approved publisher host', () {
    final canonical = sample.copyWith(
      coverUrl: 'https://cover.openbd.jp/9784488402327.jpg',
      coverSource: 'openbd',
    );
    final publisher = sample.copyWith(
      coverUrl: 'https://publisher.example/jacket.jpg',
      coverSource: 'openbd',
    );
    final legacy = sample.copyWith(
      coverUrl: 'https://cover.openbd.jp/9784488402327.jpg',
    );
    expect(BookCoverImage.isApprovedCover(canonical), true);
    expect(BookCoverImage.isApprovedCover(publisher), true);
    expect(BookCoverImage.isApprovedCover(legacy), true);
    expect(BookCoverImage.webImageStrategyForBook(publisher),
        WebHtmlElementStrategy.prefer);
  });

  test('saved or unlabeled Google, Open Library and retailer URLs are blocked', () {
    for (final url in [
      'https://books.google.com/books/content?id=test',
      'https://books.googleusercontent.com/book.jpg',
      'https://covers.openlibrary.org/b/isbn/9780140328721-M.jpg',
      'https://thumbnail.image.rakuten.co.jp/img/1.jpg',
      'https://images.weserv.nl/?url=example.org',
      'https://publisher.example/unverified.jpg',
      'https://cover.openbd.jp.evil.example/book.jpg',
      'https://books.google.com@evil.example/book.jpg',
    ]) {
      expect(BookCoverImage.isApprovedCover(sample.copyWith(coverUrl: url)),
          false, reason: url);
      expect(BookCoverImage.isApprovedCover(
        sample.copyWith(coverUrl: url, coverSource: 'openbd')),
          ![
            'books.google.com',
            'books.googleusercontent.com',
            'covers.openlibrary.org',
            'thumbnail.image.rakuten.co.jp',
            'images.weserv.nl',
          ].contains(Uri.parse(url).host), reason: url);
    }
    expect(BookCoverImage.isApprovedCover(sample.copyWith(
      coverUrl: 'https://cover.openbd.jp/book.jpg',
      coverSource: 'google_books',
    )), false);
    expect(BookCoverImage.isSafeRemoteCover('http://cover.openbd.jp/book.jpg'),
        false);
    expect(BookCoverImage.isSafeRemoteCover(
        'https://user:pass@cover.openbd.jp/book.jpg'), false);
    expect(BookCoverImage.isSafeRemoteCover(
        'https://cover.openbd.jp:8443/book.jpg'), false);
  });

  testWidgets('missing cover shows placeholder and never requests fallback services',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 138, height: 202,
        child: BookCoverImage(book: sample),
      )),
    ));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.text('表紙画像なし'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('saved Google cover cannot bypass source gate',
      (tester) async {
    final legacy = sample.copyWith(
      coverUrl:'https://books.google.com/books?id=test&img=1',
      coverSource:'google_books',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 138, height: 202,
        child: BookCoverImage(book: legacy),
      )),
    ));
    expect(find.byType(Image), findsNothing);
    expect(find.text('表紙画像なし'), findsOneWidget);
  });

  testWidgets('approved openBD cover uses HTML-first rendering',
      (tester) async {
    final approved = sample.copyWith(
      coverUrl:'https://cover.openbd.jp/9784488402327.jpg',
      coverSource:'openbd',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(
        width: 138, height: 202,
        child: BookCoverImage(book: approved),
      )),
    ));
    final target = find.byWidgetPredicate((w) =>
        w is Image && w.image is NetworkImage &&
        (w.image as NetworkImage).url == approved.coverUrl);
    expect(target, findsOneWidget);
    final image = tester.widget<Image>(target);
    expect((image.image as NetworkImage).webHtmlElementStrategy,
        WebHtmlElementStrategy.prefer);
  });
}
