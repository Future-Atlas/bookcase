import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/timeline_ad_policy.dart';

void main() {
  test('trial: one ad per two posts, only between real posts', () {
    expect(timelineAdSlotCount(0), 0);
    expect(timelineAdSlotCount(1), 0);
    expect(timelineAdSlotCount(2), 0);
    expect(timelineAdSlotCount(3), 1);
    expect(timelineAdSlotCount(4), 1);
    expect(timelineAdSlotCount(5), 2);
    expect(timelineAdSlotCount(6), 2);
    expect(timelineAdSlotCount(7), 3);
    expect(timelineAdSlotCount(100), 3);

    const postCount = 7;
    final adItems = <int>[];
    final postItems = <int>[];
    for (var i = 0; i < postCount + timelineAdSlotCount(postCount); i++) {
      if (isTimelineAdItem(i, postCount)) {
        adItems.add(i);
      } else {
        postItems.add(timelinePostIndexForItem(i, postCount));
      }
    }
    expect(adItems, <int>[2, 5, 8]);
    expect(postItems, <int>[0, 1, 2, 3, 4, 5, 6]);
  });

  test('normal: five-post interval is supported without modifying code', () {
    expect(timelineAdSlotCount(5, postsPerAd: 5), 0);
    expect(timelineAdSlotCount(6, postsPerAd: 5), 1);
    expect(timelineAdSlotCount(11, postsPerAd: 5), 2);
    expect(timelineAdSlotCount(16, postsPerAd: 5), 3);
    expect(timelineAdSlotCount(99, postsPerAd: 5), 3);
    expect(
      [for (var i = 0; i < 14; i++)
        if (isTimelineAdItem(i, 12, postsPerAd: 5)) i],
      <int>[5, 11],
    );
    expect(timelinePostIndexForItem(12, 12, postsPerAd: 5), 10);
    expect(timelinePostIndexForItem(13, 12, postsPerAd: 5), 11);
  });

  test('two home genre separators leave just one ad for the timeline', () {
    expect(homeGenreAdSlotCount, 2);
    expect(homeTimelineAdSlotStart, 2);
    expect(homeTimelineMaximumAds, 1);
    expect(homeGenreAdSlotCount + homeTimelineMaximumAds,
        timelineMaximumAdsPerPage);

    for (final postCount in <int>[0, 1, 2]) {
      expect(
        timelineAdSlotCount(postCount, maximumSlots: homeTimelineMaximumAds),
        0,
      );
    }
    for (final postCount in <int>[3, 4, 7, 100]) {
      expect(
        timelineAdSlotCount(postCount, maximumSlots: homeTimelineMaximumAds),
        1,
      );
    }

    const postCount = 7;
    final adItems = <int>[];
    final postItems = <int>[];
    final total = postCount +
        timelineAdSlotCount(postCount, maximumSlots: homeTimelineMaximumAds);
    for (var i = 0; i < total; i++) {
      if (isTimelineAdItem(
        i,
        postCount,
        maximumSlots: homeTimelineMaximumAds,
      )) {
        adItems.add(i);
      } else {
        postItems.add(timelinePostIndexForItem(
          i,
          postCount,
          maximumSlots: homeTimelineMaximumAds,
        ));
      }
    }
    expect(adItems, <int>[2]);
    expect(postItems, <int>[0, 1, 2, 3, 4, 5, 6]);
  });

  test('normal five-post interval also respects remaining page budget', () {
    expect(timelineAdSlotCount(5,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), 0);
    expect(timelineAdSlotCount(6,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), 1);
    expect(timelineAdSlotCount(99,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), 1);
    expect(isTimelineAdItem(5, 12,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), isTrue);
    expect(isTimelineAdItem(11, 12,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), isFalse);
    expect(timelinePostIndexForItem(12, 12,
        postsPerAd: 5, maximumSlots: homeTimelineMaximumAds), 11);
  });

  test('advertisement caps cannot exceed the publisher page limit', () {
    expect(timelineAdSlotCount(99, maximumSlots: 0), 0);
    expect(timelineAdSlotCount(99, maximumSlots: -3), 0);
    expect(timelineAdSlotCount(99, maximumSlots: 1), 1);
    expect(timelineAdSlotCount(99, maximumSlots: 3), 3);
    expect(timelineAdSlotCount(99, maximumSlots: 100), 3);
  });

  test('invalid ad interval inserts no advertisements', () {
    expect(timelineAdSlotCount(10, postsPerAd: 0), 0);
    expect(isTimelineAdItem(0, 10, postsPerAd: 0), false);
  });
}
