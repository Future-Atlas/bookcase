import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/reading_calendar_intro.dart';

void main() {
  for (final visit in [false, true]) {
    testWidgets('calendar announcement: visit=$visit on narrow screen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      bool? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    choice = await showDialog<bool>(
                      context: context,
                      builder: (_) => const ReadingCalendarIntro(),
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('読書カレンダー　導入！'), findsOneWidget);
      if (visit) {
        final action = find.text('読書カレンダーを見に行く');
        await tester.ensureVisible(action);
        await tester.tap(action);
      } else {
        await tester.tap(find.byTooltip('閉じる'));
      }
      await tester.pumpAndSettle();
      expect(choice, visit);
      expect(find.byType(ReadingCalendarIntro), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
