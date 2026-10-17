import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/widgets/rakuten_book_link.dart';

const link =
    'https://hb.afl.rakuten.co.jp/hgc/test/?pc=https%3A%2F%2Fbooks.rakuten.co.jp%2Frb%2F12345%2F';
const book = Book(
  id: '9784101010014',
  isbn: '9784101010014',
  title: '本',
  author: '著者',
  publisher: '',
  pubDate: '',
  coverUrl: '',
);

void main() {
  test('accepts only Rakuten affiliate links to exact book products', () {
    expect(RakutenBookLink.validatedDestination(link), isNotNull);
    for (final value in [
      '',
      'https://amazon.co.jp/dp/123',
      link.replaceFirst('https:', 'http:'),
      link.replaceFirst('books.rakuten.co.jp', 'evil.example'),
      link.replaceFirst('%2Frb%2F12345%2F', '%2Fsearch%2F'),
    ]) {
      expect(RakutenBookLink.validatedDestination(value), isNull);
    }
  });
  test('Rakuten JSON and copy preserve affiliate URL', () {
    final parsed = Book.fromRakutenJson({
      'isbn': book.isbn,
      'author': '著者',
      'affiliateUrl': link,
    });
    expect(parsed.author, '著者');
    expect(parsed.itemPrice, 0);
    expect(parsed.copyWith(title: '更新').rakutenAffiliateUrl, link);
  });
  testWidgets('official link displays affiliate disclosure and purchase button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RakutenBookLink(
            book: book.copyWith(rakutenAffiliateUrl: link),
            lookup: (_) async => throw StateError('must not fetch'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('楽天ブックスで購入する'), findsOneWidget);
    expect(find.text('広告・楽天アフィリエイトリンク'), findsOneWidget);
    expect(tester.getSize(find.byType(OutlinedButton)).width, 800);
  });
  testWidgets('purchase button displays the tax-included Rakuten price', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RakutenBookLink(
            book: book.copyWith(rakutenAffiliateUrl: link, itemPrice: 1234),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('楽天ブックスで購入する（税込1,234円）'), findsOneWidget);
  });
  testWidgets('saved book resolves and missing result hides button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RakutenBookLink(book: book, lookup: (_) async => link),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RakutenBookLink(
            book: book.copyWith(id: 'other'),
            lookup: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('lookup failure never blocks book details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RakutenBookLink(
            book: book,
            lookup: (_) async => throw Exception('offline'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
