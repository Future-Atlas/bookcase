import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/book_carousel_auto_advance.dart';

void main() {
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

  testWidgets('waits 30 idle seconds after user interaction', (tester) async {
    var advances = 0;
    final controller = BookCarouselAutoAdvance(
      onAdvance: () => advances++,
      advanceInterval: const Duration(seconds: 5),
      resumeDelay: const Duration(seconds: 30),
    )..start();
    controller.registerUserInteraction();
    await tester.pump(const Duration(seconds: 34));
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
      resumeDelay: const Duration(seconds: 30),
    )..start();
    controller.pauseForBookDetail();
    await tester.pump(const Duration(minutes: 2));
    expect(advances, 0);

    controller.resumeAfterBookDetail();
    await tester.pump(const Duration(seconds: 34));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
    controller.dispose();
  });
}
