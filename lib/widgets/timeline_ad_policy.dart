// Shared timeline advertising placement policy.
import '../config/app_environment.dart';

bool get timelineAdDisplayReady =>
    AppEnvironmentConfig.current == AppEnvironment.staging || timelineAdReady;

/// Disabled unless a Web release explicitly opts into Ninja AdMax.
const bool timelineAdEnabled = bool.fromEnvironment(
  'NINJA_ADMAX_ENABLED',
  defaultValue: false,
);

/// Temporary higher frequency for testing. Use 5 for normal operation.
const int timelinePostsPerAd = int.fromEnvironment(
  'NINJA_ADMAX_POSTS_PER_AD',
  defaultValue: 2,
);

/// The /s/ synchronous identifier must never be assumed to be an async ID.
const String ninjaAdmaxAsyncId = String.fromEnvironment(
  'NINJA_ADMAX_ASYNC_ID',
  defaultValue: '',
);

const String ninjaAdmaxAsyncType = String.fromEnvironment(
  'NINJA_ADMAX_ASYNC_TYPE',
  defaultValue: 'switch',
);

bool get timelineAdReady =>
    timelineAdEnabled &&
    ninjaAdmaxAsyncId.length >= 8 &&
    ninjaAdmaxAsyncId.length <= 128 &&
    !ninjaAdmaxAsyncId.contains(RegExp(r'[^A-Za-z0-9_-]')) &&
    (ninjaAdmaxAsyncType == 'switch' || ninjaAdmaxAsyncType == 'banner');

/// The first two unique AdMax indices belong to the book-genre separators.
/// There is intentionally no application-imposed maximum on timeline slots.
const int homeGenreAdSlotCount = 2;
const int homeTimelineAdSlotStart = homeGenreAdSlotCount;

/// Ads are only inserted between existing posts, never after the final post.
/// The number of slots is determined by available posts and the interval.
int timelineAdSlotCount(int postCount, {int postsPerAd = timelinePostsPerAd}) {
  if (postsPerAd < 1 || postCount <= postsPerAd) return 0;
  return (postCount - 1) ~/ postsPerAd;
}

bool isTimelineAdItem(
  int itemIndex,
  int postCount, {
  int postsPerAd = timelinePostsPerAd,
}) {
  if (postsPerAd < 1) return false;
  final adCount = timelineAdSlotCount(postCount, postsPerAd: postsPerAd);
  final cycle = postsPerAd + 1;
  return itemIndex >= 0 &&
      itemIndex < postCount + adCount &&
      itemIndex % cycle == postsPerAd &&
      itemIndex ~/ cycle < adCount;
}

int timelinePostIndexForItem(
  int itemIndex,
  int postCount, {
  int postsPerAd = timelinePostsPerAd,
}) {
  assert(!isTimelineAdItem(itemIndex, postCount, postsPerAd: postsPerAd));
  if (postsPerAd < 1) return itemIndex;
  final adCount = timelineAdSlotCount(postCount, postsPerAd: postsPerAd);
  final preceding = itemIndex ~/ (postsPerAd + 1);
  return itemIndex - (preceding < adCount ? preceding : adCount);
}
