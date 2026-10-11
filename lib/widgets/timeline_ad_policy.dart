/// Shared timeline advertising placement policy.
    
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

/// Ninja AdMax recommends no more than three advertisements per page.
const int timelineMaximumAdsPerPage = 3;

/// Two genre separator ads are reserved on the real home page.
/// The embedded timeline can use the one remaining placement.
const int homeGenreAdSlotCount = 2;
const int homeTimelineAdSlotStart = homeGenreAdSlotCount;
const int homeTimelineMaximumAds =
    timelineMaximumAdsPerPage - homeGenreAdSlotCount;

/// Ads are only inserted between posts, never after the final post.
int timelineAdSlotCount(
  int postCount, {
  int postsPerAd = timelinePostsPerAd,
  int maximumSlots = timelineMaximumAdsPerPage,
}) {
  if (postsPerAd < 1 || postCount <= postsPerAd || maximumSlots <= 0) {
    return 0;
  }
  final allowedSlots = maximumSlots > timelineMaximumAdsPerPage
      ? timelineMaximumAdsPerPage
      : maximumSlots;
  final possibleSlots = (postCount - 1) ~/ postsPerAd;
  return possibleSlots < allowedSlots ? possibleSlots : allowedSlots;
}

bool isTimelineAdItem(
  int itemIndex,
  int postCount, {
  int postsPerAd = timelinePostsPerAd,
  int maximumSlots = timelineMaximumAdsPerPage,
}) {
  if (postsPerAd < 1) return false;
  final adCount = timelineAdSlotCount(
    postCount,
    postsPerAd: postsPerAd,
    maximumSlots: maximumSlots,
  );
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
  int maximumSlots = timelineMaximumAdsPerPage,
}) {
  assert(!isTimelineAdItem(
    itemIndex,
    postCount,
    postsPerAd: postsPerAd,
    maximumSlots: maximumSlots,
  ));
  if (postsPerAd < 1) return itemIndex;
  final adCount = timelineAdSlotCount(
    postCount,
    postsPerAd: postsPerAd,
    maximumSlots: maximumSlots,
  );
  final preceding = itemIndex ~/ (postsPerAd + 1);
  return itemIndex - (preceding < adCount ? preceding : adCount);
}
