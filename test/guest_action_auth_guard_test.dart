import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('book read action authenticates before opening the composer', () {
    final source = File(
      'lib/widgets/book_detail_dialog.dart',
    ).readAsStringSync();
    final readActionStart = source.indexOf(
      'onPressed: isRead || checking',
    );
    final authentication = source.indexOf(
      '.ensureAuthenticated()',
      readActionStart,
    );
    final closeDetails = source.indexOf(
      'Navigator.of(context).pop()',
      readActionStart,
    );

    expect(readActionStart, greaterThanOrEqualTo(0));
    expect(authentication, greaterThan(readActionStart));
    expect(closeDetails, greaterThan(authentication));
  });

  test('profile social actions authenticate before changing or listing follows', () {
    final source = File(
      'lib/screens/user_profile_screen.dart',
    ).readAsStringSync();

    final toggleFollow = source.indexOf('Future<void> _toggleFollow()');
    final toggleAuthentication = source.indexOf(
      'if (!await _ensureAuthenticated()',
      toggleFollow,
    );
    final followMutation = source.indexOf(
      'await service.followProfile(profile.id)',
      toggleFollow,
    );
    expect(toggleFollow, greaterThanOrEqualTo(0));
    expect(toggleAuthentication, greaterThan(toggleFollow));
    expect(followMutation, greaterThan(toggleAuthentication));

    final openList = source.indexOf('Future<void> _openFollowList');
    final listAuthentication = source.indexOf(
      'if (!await _ensureAuthenticated()',
      openList,
    );
    final listNavigation = source.indexOf('FollowListScreen(', openList);
    expect(openList, greaterThanOrEqualTo(0));
    expect(listAuthentication, greaterThan(openList));
    expect(listNavigation, greaterThan(listAuthentication));
  });
}
