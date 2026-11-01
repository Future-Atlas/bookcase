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
  test('Open Library fallback uses the requested edition ISBN and a real 404 on missing', () {
    expect(
      BookCoverImage.openLibraryCoverUrl('9784488402327'),
      'https://covers.openlibrary.org/b/isbn/9784488402327-M.jpg?default=false',
    );
    expect(
      BookCoverImage.openLibraryCoverUrl('978-4-488-40232-7'),
      BookCoverImage.openLibraryCoverUrl('9784488402327'),
    );
    expect(BookCoverImage.openLibraryCoverUrl('123'), null);
    expect(BookCoverImage.openLibraryCoverUrl('javascript:alert(1)'), null);
    expect(BookCoverImage.openLibraryCoverUrl('9784488402327/../'), null);
    expect(BookCoverImage.openLibraryCoverUrl(''), null);
  });

  test('remote primary image must be HTTPS, with no embedded credentials', () {
    expect(BookCoverImage.isSafeRemoteCover('https://example.org/jacket.png'), true);
    expect(BookCoverImage.isSafeRemoteCover('http://example.org/jacket.png'), false);
    expect(BookCoverImage.isSafeRemoteCover('javascript:alert(1)'), false);
    expect(BookCoverImage.isSafeRemoteCover('https://me:pass@example.org/jacket.png'), false);
    expect(BookCoverImage.isSafeRemoteCover(''), false);
  });

  test('known cover CDNs use HTML-first rendering to avoid Flutter Web CORS fetch', () {
    for (final url in [
      'https://cover.openbd.jp/9784866162591.jpg',
      'https://books.google.com/books/content?id=sample&img=1',
      'https://books.googleusercontent.com/some-cover.jpg',
      'https://covers.openlibrary.org/b/isbn/9780140328721-M.jpg?default=false',
    ]) {
      expect(BookCoverImage.webImageStrategyForUrl(url),
          WebHtmlElementStrategy.prefer, reason: url);
    }
    for (final url in [
      'https://books.google.com.evil.example/cover.jpg',
      'https://books.google.com@evil.example/cover.jpg',
      'https://evil.example/cover.jpg?site=cover.openbd.jp',
      'https://covers.openlibrary.org.evil.example/jacket.jpg',
      'https://user:pass@books.google.com/cover.jpg',
      'http://cover.openbd.jp/cover.jpg',
      'https://books.google.com:8443/cover.jpg',
      'https://publisher.example/cover.jpg',
      'not-a-valid-url',
    ]) {
      expect(BookCoverImage.webImageStrategyForUrl(url),
          WebHtmlElementStrategy.fallback, reason: url);
    }
  });

  testWidgets('book images use the HTML-first setting for Google and openBD', (tester) async {
    for (final url in [
      'https://books.google.com/books/content?id=sample&img=1',
      'https://cover.openbd.jp/9784866162591.jpg',
    ]) {
      final covered = sample.copyWith(coverUrl: url);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SizedBox(
          width: 138, height: 202,
          child: BookCoverImage(book: covered),
        )),
      ));
      // A failed image may render an ISBN fallback Image as a child, so
      // target this provider URL instead of assuming there is only one Image.
      final target = find.byWidgetPredicate((widget) =>
          widget is Image && widget.image is NetworkImage &&
          (widget.image as NetworkImage).url == url);
      expect(target, findsOneWidget);
      final image = tester.widget<Image>(target);
      expect((image.image as NetworkImage).webHtmlElementStrategy,
          WebHtmlElementStrategy.prefer);
    }
  });

  testWidgets('missing ISBN does not create a network image or a fake jacket', (tester) async {
    final invalid = sample.copyWith(id: 'invalid', isbn: 'invalid');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 138,
          height: 202,
          child: BookCoverImage(book: invalid),
        ),
      ),
    ));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.text('表紙画像なし'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('valid new ISBN attempts Open Library rather than showing the icon immediately', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 138,
          height: 202,
          child: BookCoverImage(book: sample),
        ),
      ),
    ));
    final network = tester.widget<Image>(find.byType(Image));
    expect((network.image as NetworkImage).url,
      BookCoverImage.openLibraryCoverUrl(sample.isbn));
  });
  testWidgets('Google Books thumbnail keeps visible source attribution', (tester) async {
    final credited = sample.copyWith(
      coverUrl: 'https://books.google.com/books?id=example&img=1',
      coverSource: 'google_books',
      coverAttributionUrl: 'https://books.google.com/books?id=example',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 138, height: 202,
          child: BookCoverImage(book: credited),
        ),
      ),
    ));
    final primary = tester.widget<Image>(find.byType(Image));
    final context = tester.element(find.byType(Image));
    expect(primary.frameBuilder, isNotNull);

    // Before the first successful image frame, do not attribute a cover that
    // has not been displayed. Once loaded, the badge must be visible.
    final pending = primary.frameBuilder!(
      context, const ColoredBox(color: Colors.black), null, false,
    );
    final loaded = primary.frameBuilder!(
      context, const ColoredBox(color: Colors.black), 0, false,
    );
    // Simulate a rejected Google image: the ISBN-specific Open Library image
    // is used instead, with no misleading Google attribution over the top.
    final failed = primary.errorBuilder!(
      context, StateError('image unavailable'), StackTrace.empty,
    );
    Widget frame(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 138, height: 202, child: child),
      ),
    );

    await tester.pumpWidget(frame(pending));
    expect(find.text('Google ブックス'), findsNothing);
    await tester.pumpWidget(frame(loaded));
    expect(find.text('Google ブックス'), findsOneWidget);
    expect(find.byTooltip('表紙画像の情報：Google ブックス'), findsOneWidget);
    await tester.pumpWidget(frame(failed));
    expect(find.text('Google ブックス'), findsNothing);
    expect(find.byTooltip('表紙画像の情報：Google ブックス'), findsNothing);
    final fallback = tester.widget<Image>(find.byType(Image));
    expect((fallback.image as NetworkImage).url,
        BookCoverImage.openLibraryCoverUrl(sample.isbn));
  });

}
