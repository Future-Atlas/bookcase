import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/book_detail_dialog_frame.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-book-detail'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => const BookDetailDialogFrame(
              child: SizedBox(width: 320, height: 240),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-book-detail')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('book detail close button is white in dark mode and closes', (
    tester,
  ) async {
    await _openDialog(tester, brightness: Brightness.dark);

    final finder = find.byKey(const ValueKey('book-detail-close-button'));
    expect(finder, findsOneWidget);
    expect(tester.widget<IconButton>(finder).color, Colors.white);

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(finder, findsNothing);
  });

  testWidgets('book detail close button is black in light mode', (
    tester,
  ) async {
    await _openDialog(tester, brightness: Brightness.light);

    final finder = find.byKey(const ValueKey('book-detail-close-button'));
    expect(finder, findsOneWidget);
    expect(tester.widget<IconButton>(finder).color, Colors.black);
    final dialogBody = find.byType(Material).last;
    expect(tester.getTopLeft(finder).dx, lessThan(tester.getCenter(dialogBody).dx));
  });
}
