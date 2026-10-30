import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/screens/profile_onboarding_screen.dart';

void main() {
  testWidgets('再設定時は初回設定と同じ形式で新しいパスワードを設定する', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyPasswordSetupScreen(
          isRecovery: true,
          onCompleted: () {},
        ),
      ),
    );

    expect(find.text('新しいパスワードを設定'), findsOneWidget);
    expect(find.text('新しいパスワード'), findsOneWidget);
    expect(find.text('新しいパスワード（確認）'), findsOneWidget);
    expect(find.text('再設定する'), findsOneWidget);
    expect(find.text('個人情報変更用パスワードを設定してください'), findsNothing);
  });

  testWidgets('初回設定画面の案内とボタンは変わらない', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyPasswordSetupScreen(onCompleted: () {}),
      ),
    );

    expect(find.text('個人情報変更用パスワードを設定してください'), findsOneWidget);
    expect(find.text('パスワード'), findsOneWidget);
    expect(find.text('パスワード（確認）'), findsOneWidget);
    expect(find.text('設定する'), findsOneWidget);
    expect(find.text('新しいパスワードを設定'), findsNothing);
  });
}
