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
    await tester.pump(const Duration(seconds: 11));
    expect(first, 1);
    await tester.pump(const Duration(milliseconds: 500));
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
}
