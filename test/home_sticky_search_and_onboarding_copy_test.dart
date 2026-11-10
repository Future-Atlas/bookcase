import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home search stays outside the scrolling content', () {
    final source = File('lib/screens/book_list_screen.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final stickySearch = source.indexOf(
      "ValueKey('home-sticky-search')",
      buildStart,
    );
    final expandedScroll = source.indexOf('Expanded(', stickySearch);
    final scrollView = source.indexOf('SingleChildScrollView(', expandedScroll);
    final hero = source.indexOf('_buildTopHeroImage()', scrollView);

    expect(buildStart, greaterThanOrEqualTo(0));
    expect(stickySearch, greaterThan(buildStart));
    expect(expandedScroll, greaterThan(stickySearch));
    expect(scrollView, greaterThan(expandedScroll));
    expect(hero, greaterThan(scrollView));
    expect(
      source.substring(stickySearch, expandedScroll),
      contains('_buildSearchBar()'),
    );
  });

  test('registration fields explicitly support selection copy and paste', () {
    final source = File(
      'lib/screens/profile_onboarding_screen.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'enableInteractiveSelection:\s*true').allMatches(source).length,
      greaterThanOrEqualTo(6),
    );
    expect(source, contains("tooltip: 'パスワードをコピー'"));
    expect(source, contains('Clipboard.setData'));
    expect(source, contains('Icons.copy_outlined'));
  });
}
