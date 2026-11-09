import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/profile_page_color.dart';
import 'package:sharemarium/widgets/profile_color_border.dart';

void main() {
  testWidgets('uses the listed user page color for all four border sides', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileColorBorder(pageColorKey: 'red', child: Text('user')),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ProfileColorBorder),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = decoratedBox.decoration as BoxDecoration;
    final border = decoration.border! as Border;

    expect(border.top.color, ProfilePageColors.colorFor('red'));
    expect(border.right.color, ProfilePageColors.colorFor('red'));
    expect(border.bottom.color, ProfilePageColors.colorFor('red'));
    expect(border.left.color, ProfilePageColors.colorFor('red'));
    expect(border.top.width, ProfileColorBorder.borderWidth);
  });

  testWidgets('falls back to yellow for an unknown page color', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileColorBorder(
            pageColorKey: 'unknown',
            child: Text('user'),
          ),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ProfileColorBorder),
        matching: find.byType(DecoratedBox),
      ),
    );
    final border = (decoratedBox.decoration as BoxDecoration).border! as Border;
    expect(border.top.color, ProfilePageColors.colorFor('yellow'));
  });

  test('follow and engagement lists render separate colored user boxes', () {
    for (final path in const [
      'lib/screens/follow_list_screen.dart',
      'lib/screens/post_engagement_users_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('ProfileColorBorder('));
      expect(source, contains('pageColorKey: profile.pageColorKey'));
      expect(source, contains('const SizedBox(height: 6)'));
    }
  });
}
