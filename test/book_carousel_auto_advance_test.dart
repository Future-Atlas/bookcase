import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/book_carousel_auto_advance.dart';

void main() {
  testWidgets('default interval is 1.5 seconds and pauses are section-local', (
    tester,
  ) async {
    var first = 0;
    var second = 0;
    final a = BookCarouselAutoAdvance(onAdvance: () => first++)..start();
    final b = BookCarouselAutoAdvance(onAdvance: () => second++)..start();
    await tester.pump(const Duration(milliseconds: 1500));
    expect([first, second], [1, 1]);
    a.registerUserInteraction();
    await tester.pump(const Duration(milliseconds: 1500));
    expect([first, second], [1, 2]);
    a.pauseForBookDetail();
    await tester.pump(const Duration(seconds: 30));
    expect(first, 1);
    a.resumeAfterBookDetail();
    await tester.pump(const Duration(seconds: 14));
    expect(first, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(first, 2);
    a.dispose();
    b.dispose();
  });
  testWidgets('advances periodically after starting', (tester) async {
    var advances = 0;
    final controller = BookCarouselAutoAdvance(
      onAdvance: () => advances++,
      advanceInterval: const Duration(seconds: 5),
    )..start();
    await tester.pump(const Duration(seconds: 4));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
    controller.dispose();
  });

  testWidgets('waits 10 idle seconds after user interaction', (tester) async {
    var advances = 0;
    final controller = BookCarouselAutoAdvance(
      onAdvance: () => advances++,
      advanceInterval: const Duration(seconds: 5),
      resumeDelay: const Duration(seconds: 10),
    )..start();
    controller.registerUserInteraction();
    await tester.pump(const Duration(seconds: 14));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
    controller.dispose();
  });

  testWidgets('does not count time while book details are open', (
    tester,
  ) async {
    var advances = 0;
    final controller = BookCarouselAutoAdvance(
      onAdvance: () => advances++,
      advanceInterval: const Duration(seconds: 5),
      resumeDelay: const Duration(seconds: 10),
    )..start();
    controller.pauseForBookDetail();
    await tester.pump(const Duration(minutes: 2));
    expect(advances, 0);

    controller.resumeAfterBookDetail();
    await tester.pump(const Duration(seconds: 14));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
    controller.dispose();
  });

  testWidgets('hover or touch holds pause until 15 seconds after release', (
    tester,
  ) async {
    var advances = 0;
    final hover = Object();
    final touch = Object();
    final controller = BookCarouselAutoAdvance(
      onAdvance: () => advances++,
      advanceInterval: const Duration(milliseconds: 1500),
      holdResumeDelay: const Duration(seconds: 15),
    )..start();

    controller.beginInteractionHold(hover);
    controller.beginInteractionHold(touch);
    controller.registerUserInteraction();
    await tester.pump(const Duration(minutes: 1));
    expect(advances, 0);

    controller.endInteractionHold(touch);
    await tester.pump(const Duration(seconds: 30));
    expect(advances, 0, reason: 'hover still holds this carousel');

    controller.endInteractionHold(hover);
    await tester.pump(const Duration(seconds: 14));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(advances, 2);
    controller.dispose();
  });

  test('page scrolling is not treated as a carousel interaction', () {
    final source = File('lib/screens/book_list_screen.dart').readAsStringSync();
    expect(
      source,
      isNot(contains('onPointerDown: (_) => registerUserInteraction()')),
    );
    expect(
      source,
      isNot(contains('onPointerMove: (_) => registerUserInteraction()')),
    );
    expect(
      source,
      isNot(contains('onPointerSignal: (_) => registerUserInteraction()')),
    );
    expect(source, contains('notification.metrics.axis != Axis.horizontal'));
    expect(source, contains('notification.dragDetails != null'));
    expect(source, contains('_beginInteractionHold(_hoverInteraction)'));
    expect(source, contains('_endInteractionHold(_hoverInteraction)'));
    expect(source, contains('_beginInteractionHold(_pointerInteraction)'));
    expect(source, contains('_endInteractionHold(_pointerInteraction)'));
    expect(
      source,
      contains('_scrollController.jumpTo(_scrollController.offset)'),
    );
  });
}
