import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/book_page_bar.dart';

void main() {
  testWidgets('bar is visible on page one and a drag requests one next page', (
    tester,
  ) async {
    var next = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: BookPageBar(
              pageNumber: 1,
              canLoadPrevious: false,
              hasMore: true,
              isLoading: false,
              onNext: () => next++,
              onPrevious: () => fail('No previous page'),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.dragFrom(
      tester.getTopLeft(find.byType(Slider)) + const Offset(24, 16),
      const Offset(280, 0),
    );
    await tester.pumpAndSettle();
    expect(next, 1);
  });

  testWidgets('left drag requests previous page and loading disables the bar', (
    tester,
  ) async {
    var previous = 0;
    Future<void> render(bool loading) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: BookPageBar(
              pageNumber: 2,
              canLoadPrevious: true,
              hasMore: true,
              isLoading: loading,
              onNext: () {},
              onPrevious: () => previous++,
            ),
          ),
        ),
      ),
    );
    await render(false);
    await tester.drag(find.byType(Slider), const Offset(-160, 0));
    await tester.pumpAndSettle();
    expect(previous, 1);
    await render(true);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });

  testWidgets('bar remains visible when there are no more pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookPageBar(
            pageNumber: 1,
            canLoadPrevious: false,
            hasMore: false,
            isLoading: false,
            onNext: () => fail('No next page'),
            onPrevious: () => fail('No previous page'),
          ),
        ),
      ),
    );
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
  });
}
