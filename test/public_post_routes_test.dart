import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/screens/public_post_routes.dart';
import 'package:sharemarium/screens/book_list_screen.dart';

void main() {
  testWidgets('public timeline uses the same home timeline component', (
    tester,
  ) async {
    late Scaffold screen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            screen = const PublicPostsScreen().build(context) as Scaffold;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      (screen.appBar as AppBar).title,
      isA<Text>().having((text) => text.data, 'title', 'タイムライン'),
    );
    expect(
      screen.body,
      isA<BookListScreen>().having(
        (screen) => screen.timelineOnly,
        'timelineOnly',
        true,
      ),
    );
  });
  test('post index and review permalinks have Flutter routes', () {
    for (final name in [
      '/posts',
      '/posts?test=1',
      '/posts/11111111-1111-4111-8111-111111111111',
    ]) {
      final route = publicPostRoute(RouteSettings(name: name));
      expect(route, isNotNull);
      expect(route!.settings.name, name);
    }
  });
  test('other paths and malformed post IDs are not post routes', () {
    for (final name in ['/', '/mypage', '/posts/not-a-uuid', '/posts/a/b']) {
      expect(publicPostRoute(RouteSettings(name: name)), isNull);
    }
  });
}
