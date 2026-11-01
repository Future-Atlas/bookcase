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
    expect(find.text('Google ブックス'), findsOneWidget);
    expect(find.byTooltip('表紙画像の情報：Google ブックス'), findsOneWidget);
  });

}
