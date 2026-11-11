import '../models/post.dart';

class TimelineRankingService {
  const TimelineRankingService._();

  static List<Post> arrange({
    required Iterable<Post> posts,
    required Set<String> followedProfileIds,
  }) {
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

    followedPosts.sort(_compareByPopularity);
    popularPosts.sort(_compareByPopularity);

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
  }) {
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

    preferred.sort(_compareByPopularity);
    followed.sort(_compareByPopularity);
    others.sort(_compareByPopularity);
    return [...preferred, ...followed, ...others];
  }

  static int _compareByPopularity(Post first, Post second) {
    final scoreComparison = second.reactionScore.compareTo(first.reactionScore);
    if (scoreComparison != 0) return scoreComparison;
    return second.createdAt.compareTo(first.createdAt);
  }
}
