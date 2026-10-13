import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/public_posts_link.dart';

void main() {
  for (final compact in <bool>[false, true]) {
    testWidgets(
      compact
          ? 'compact header navigation opens the public posts index'
          : 'home navigation opens the public posts index',
      (tester) async {
        String? openedRoute;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: PublicPostsLink(compact: compact)),
            ),
            onGenerateRoute: (settings) {
              openedRoute = settings.name;
              return MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Center(child: Text('投稿一覧ページ'))),
              );
            },
          ),
        );

        if (compact) {
          expect(find.text('タイムライン'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('header-public-posts-link')),
          );
        } else {
          expect(find.text('タイムラインを見る'), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('home-public-posts-link')),
          );
        }
        await tester.pumpAndSettle();

        expect(openedRoute, '/posts');
        expect(find.text('投稿一覧ページ'), findsOneWidget);
      },
    );
  }

  testWidgets('home timeline heading opens the full timeline', (tester) async {
    String? openedRoute;
    const accent = Color(0xFF20E0D0);
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(
          body: PublicPostsLink(sectionHeading: true, foregroundColor: accent),
        ),
        onGenerateRoute: (settings) {
          openedRoute = settings.name;
          return MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('全画面タイムライン')),
          );
        },
      ),
    );

    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('home-timeline-heading-link')),
    );
    expect(button.style?.foregroundColor?.resolve({}), accent);
    await tester.tap(find.text('タイムライン'));
    await tester.pumpAndSettle();
    expect(openedRoute, '/posts');
    expect(find.text('全画面タイムライン'), findsOneWidget);
  });
}
