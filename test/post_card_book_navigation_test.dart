import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/post.dart';
import 'package:sharemarium/widgets/post_card.dart';

final _post = Post(
  id: 'post-1',
  profileId: 'profile-1',
  bookId: '9784101269313',
  rating: 4,
  comment: '感想',
  createdAt: DateTime(2026, 10, 15),
  username: 'ユーザー',
  userAvatarUrl: '',
  bookTitle: '何者',
  bookAuthor: '朝井 リョウ',
  bookCoverUrl: 'https://example.com/cover.jpg',
);

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Size size,
    required VoidCallback onBookTap,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PostCard(post: _post, onBookTap: onBookTap),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('desktop cover and title open the book details', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await pumpCard(tester, size: const Size(900, 900), onBookTap: () => taps++);

    await tester.tap(find.byKey(const ValueKey('post-book-cover-post-1')));
    await tester.tap(find.byKey(const ValueKey('post-book-title-post-1')));
    expect(taps, 2);
  });

  testWidgets('mobile cover and title open the book details', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var taps = 0;
    await pumpCard(tester, size: const Size(390, 900), onBookTap: () => taps++);

    await tester.tap(find.byKey(const ValueKey('post-book-cover-post-1')));
    await tester.tap(find.byKey(const ValueKey('post-book-title-post-1')));
    expect(taps, 2);
  });
}
