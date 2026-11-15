import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/primary_bottom_navigation.dart';

void main() {
  testWidgets('the primary footer shows all three destinations in order', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: PrimaryBottomNavigation(
            accentColor: Colors.red,
            selectedIndex: 1,
            onTimeline: () => tapped.add('timeline'),
            onHome: () => tapped.add('home'),
            onMyPage: () => tapped.add('mypage'),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('timeline-double-arrow-down')), findsOneWidget);
    expect(find.text('▽'), findsNothing);
    expect(find.text('△'), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    final timeline = find.byKey(const ValueKey('primary-footer-timeline'));
    final home = find.byKey(const ValueKey('primary-footer-home'));
    final profile = find.byKey(const ValueKey('primary-footer-profile'));
    expect(tester.getTopLeft(timeline).dx, lessThan(tester.getTopLeft(home).dx));
    expect(tester.getTopLeft(home).dx, lessThan(tester.getTopLeft(profile).dx));

    await tester.tap(timeline);
    await tester.tap(home);
    await tester.tap(profile);
    expect(tapped, ['timeline', 'home', 'mypage']);
    expect(tester.takeException(), isNull);
  });
}
