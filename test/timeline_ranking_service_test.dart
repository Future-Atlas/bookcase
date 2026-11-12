import 'package:sharemarium/models/post.dart';
import 'package:sharemarium/models/social_models.dart';
import 'package:sharemarium/services/timeline_ranking_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('30-day decay halves the reaction score after 30 days', () {
    final now = DateTime.utc(2026, 11, 12);
    final post = _post('old', 'other', likes: 10, createdAt: now.subtract(const Duration(days: 30)));
    expect(TimelineRankingService.decayedScore(post, now), 5.0);
    expect(TimelineRankingService.decayedScore(_post('new', 'other', likes: 10, createdAt: now), now), 10.0);
  });

  test('newer post can outrank older post with more raw reactions', () {
    final now = DateTime.utc(2026, 11, 12);
    final arranged = TimelineRankingService.arrange(
      posts: [
        _post('older', 'other', likes: 15, createdAt: now.subtract(const Duration(days: 60))),
        _post('newer', 'other', likes: 10, createdAt: now),
      ],
      followedProfileIds: const {},
      now: now,
    );
    expect(arranged.map((post) => post.id), ['newer', 'older']);
  });

  test('future timestamps do not receive a ranking bonus', () {
    final now = DateTime.utc(2026, 11, 12);
    final future = _post('future', 'other', likes: 10, createdAt: now.add(const Duration(days: 1)));
    expect(TimelineRankingService.decayedScore(future, now), 10.0);
  });

  test('followed and popular posts alternate starting with followed', () {
    final arranged = TimelineRankingService.arrange(
      posts: [
        _post('popular-low', 'other-1', likes: 1),
        _post('follow-low', 'followed-1', likes: 2),
        _post('popular-high', 'other-2', likes: 8),
        _post('follow-high', 'followed-2', loves: 5),
        _post('popular-mid', 'other-3', likes: 4),
      ],
      followedProfileIds: const {'followed-1', 'followed-2'},
    );

    expect(arranged.map((post) => post.id), [
      'follow-high',
      'popular-high',
      'follow-low',
      'popular-mid',
      'popular-low',
    ]);
  });

  test('popular posts remain score ordered when there are no follows', () {
    final arranged = TimelineRankingService.arrange(
      posts: [
        _post('low', 'other-1', likes: 1),
        _post('high', 'other-2', loves: 2),
      ],
      followedProfileIds: const {},
    );

    expect(arranged.map((post) => post.id), ['high', 'low']);
  });

  test('book reviews put every followed profile before other profiles', () {
    final arranged = TimelineRankingService.arrangeBookReviews(
      posts: [
        _post('other-high', 'other-1', loves: 9),
        _post('follow-low', 'followed-1', likes: 1),
        _post('follow-high', 'followed-2', loves: 2),
        _post('other-low', 'other-2'),
      ],
      followedProfileIds: const {'followed-1', 'followed-2'},
    );

    expect(arranged.map((post) => post.id), [
      'follow-high',
      'follow-low',
      'other-high',
      'other-low',
    ]);
  });

  test('profile book reviews put the viewed profile owner first', () {
    final arranged = TimelineRankingService.arrangeBookReviews(
      posts: [
        _post('other-high', 'other-1', loves: 9),
        _post('owner-low', 'profile-owner'),
        _post('follow-high', 'followed-1', loves: 5),
        _post('owner-high', 'profile-owner', likes: 3),
      ],
      followedProfileIds: const {'followed-1'},
      preferredProfileId: 'profile-owner',
    );

    expect(arranged.map((post) => post.id), [
      'owner-high',
      'owner-low',
      'follow-high',
      'other-high',
    ]);
  });
}

Post _post(
  String id,
  String profileId, {
  int likes = 0,
  int loves = 0,
  int sad = 0,
  DateTime? createdAt,
}) {
  return Post(
    id: id,
    profileId: profileId,
    bookId: 'book-$id',
    rating: 4,
    comment: 'review',
    createdAt: createdAt ?? DateTime.utc(2026, 8, 27),
    username: profileId,
    userAvatarUrl: '',
    bookTitle: id,
    bookAuthor: 'author',
    bookCoverUrl: '',
    reactionCounts: {
      PostReactionType.like: likes,
      PostReactionType.love: loves,
      PostReactionType.sad: sad,
    },
  );
}
