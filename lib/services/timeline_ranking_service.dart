import '../models/post.dart';

class TimelineRankingService {
  const TimelineRankingService._();

  static List<Post> arrange({
    required Iterable<Post> posts,
    required Set<String> followedProfileIds,
    DateTime? now,
  }) {
    final rankingTime = now ?? DateTime.now();
    final followedPosts = <Post>[];
    final popularPosts = <Post>[];
    final seenPostIds = <String>{};

    for (final post in posts) {
      if (!seenPostIds.add(post.id)) continue;
      if (followedProfileIds.contains(post.profileId)) {
        followedPosts.add(post);
      } else {
        popularPosts.add(post);
      }
    }

    followedPosts.sort((a, b) => _compareByPopularity(a, b, rankingTime));
    popularPosts.sort((a, b) => _compareByPopularity(a, b, rankingTime));

    if (followedPosts.isEmpty) return popularPosts;
    if (popularPosts.isEmpty) return followedPosts;

    final arranged = <Post>[];
    final maxLength = followedPosts.length > popularPosts.length
        ? followedPosts.length
        : popularPosts.length;
    for (var index = 0; index < maxLength; index++) {
      if (index < followedPosts.length) arranged.add(followedPosts[index]);
      if (index < popularPosts.length) arranged.add(popularPosts[index]);
    }
    return arranged;
  }

  /// Groups book reviews by navigation context while preserving the existing
  /// popularity order inside every group.
  ///
  /// A profile page can nominate its owner with [preferredProfileId]. Reviews
  /// from followed profiles then come before all remaining public reviews.
  static List<Post> arrangeBookReviews({
    required Iterable<Post> posts,
    required Set<String> followedProfileIds,
    String? preferredProfileId,
    DateTime? now,
  }) {
    final rankingTime = now ?? DateTime.now();
    final preferred = <Post>[];
    final followed = <Post>[];
    final others = <Post>[];
    final seenPostIds = <String>{};
    final normalizedPreferred = preferredProfileId?.trim() ?? '';

    for (final post in posts) {
      if (!seenPostIds.add(post.id)) continue;
      if (normalizedPreferred.isNotEmpty &&
          post.profileId == normalizedPreferred) {
        preferred.add(post);
      } else if (followedProfileIds.contains(post.profileId)) {
        followed.add(post);
      } else {
        others.add(post);
      }
    }

    preferred.sort((a, b) => _compareByPopularity(a, b, rankingTime));
    followed.sort((a, b) => _compareByPopularity(a, b, rankingTime));
    others.sort((a, b) => _compareByPopularity(a, b, rankingTime));
    return [...preferred, ...followed, ...others];
  }

  /// Decayed score = existing reaction score / (1 + days since posting / 30).
  /// Future timestamps are treated as freshly posted to avoid a bonus.
  static double decayedScore(Post post, DateTime now) {
    final elapsedMs = now.difference(post.createdAt).inMilliseconds;
    final elapsedDays = elapsedMs <= 0
        ? 0.0
        : elapsedMs / Duration.millisecondsPerDay;
    return post.reactionScore / (1 + elapsedDays / 30);
  }

  static int _compareByPopularity(Post first, Post second, DateTime now) {
    final scoreComparison = decayedScore(second, now)
        .compareTo(decayedScore(first, now));
    if (scoreComparison != 0) return scoreComparison;
    final dateComparison = second.createdAt.compareTo(first.createdAt);
    if (dateComparison != 0) return dateComparison;
    return first.id.compareTo(second.id);
  }
}
