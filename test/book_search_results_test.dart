import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/book.dart';
import 'package:sharemarium/widgets/book_search_results.dart';
import 'package:sharemarium/widgets/timeline_ad_slot.dart';

void main() {
  testWidgets('40 books have two separate 20-book batches and two ad slots', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final books = List.generate(
      40,
      (i) => Book(
        id: '$i',
        title: 'Book $i',
        author: 'Author',
        publisher: '',
        pubDate: '',
        isbn: '',
        coverUrl: '',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BookSearchResults(books: books, onTap: (_) {}),
          ),
        ),
      ),
    );
    expect(find.byType(GridView), findsNWidgets(4));
    expect(find.byType(TimelineAdSlot), findsNWidgets(2));
    for (final grid in tester.widgetList<GridView>(find.byType(GridView))) {
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        5,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
