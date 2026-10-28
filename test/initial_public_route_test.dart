import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/utils/initial_public_route.dart';

void main() {
  test('clean and legacy hash book links open the same book', () {
    for (final url in [
      'https://www.sharemarium.com/book/9784101269313',
      'https://www.sharemarium.com/book/9784101269313/?utm_source=google',
      'https://www.sharemarium.com/#/book/9784101269313',
    ]) {
      expect(initialPublicRoute(Uri.parse(url)), '/book/9784101269313');
    }
  });
  test('OAuth and home visits do not open a stale book', () {
    expect(
      initialPublicRoute(Uri.parse('https://www.sharemarium.com/')),
      isNull,
    );
    expect(
      initialPublicRoute(Uri.parse('https://www.sharemarium.com/?code=test')),
      isNull,
    );
    expect(
      initialPublicRoute(
        Uri.parse('https://www.sharemarium.com/#access_token=test'),
      ),
      isNull,
    );
  });
}
