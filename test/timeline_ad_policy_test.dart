import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/widgets/timeline_ad_policy.dart';

void main() {
  test('ads are inserted between real posts at the configured interval', () {
    expect(timelineAdSlotCount(0), 0);
    expect(timelineAdSlotCount(1), 0);
    expect(timelineAdSlotCount(2), 0);
    expect(timelineAdSlotCount(3), 0);
    expect(timelineAdSlotCount(4), 0);
    expect(timelineAdSlotCount(5), 0);
    expect(timelineAdSlotCount(6), 1);
    expect(timelineAdSlotCount(7), 1);
    expect(timelineAdSlotCount(9), 1);
    expect(timelineAdSlotCount(21), 4);
    expect(timelineAdSlotCount(100), 19);
    expect(timelineAdSlotCount(1000), 199);

    const postCount = 9;
    final ads = <int>[];
    final posts = <int>[];
    final total = postCount + timelineAdSlotCount(postCount);
    for (var i = 0; i < total; i++) {
      if (isTimelineAdItem(i, postCount)) {
        ads.add(i);
      } else {
        posts.add(timelinePostIndexForItem(i, postCount));
      }
    }
    expect(ads, <int>[5]);
    expect(posts, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('five-post interval works without a hard slot limit', () {
    expect(timelineAdSlotCount(5, postsPerAd: 5), 0);
    expect(timelineAdSlotCount(6, postsPerAd: 5), 1);
    expect(timelineAdSlotCount(11, postsPerAd: 5), 2);
    expect(timelineAdSlotCount(16, postsPerAd: 5), 3);
    expect(timelineAdSlotCount(99, postsPerAd: 5), 19);
    expect(timelineAdSlotCount(101, postsPerAd: 5), 20);
    expect(
      [
        for (var i = 0; i < 14; i++)
          if (isTimelineAdItem(i, 12, postsPerAd: 5)) i,
      ],
      <int>[5, 11],
    );
    expect(timelinePostIndexForItem(12, 12, postsPerAd: 5), 10);
    expect(timelinePostIndexForItem(13, 12, postsPerAd: 5), 11);
  });

  test('the two book-genre ads do not reduce the timeline inventory', () {
    expect(homeGenreAdSlotCount, 2);
    expect(homeTimelineAdSlotStart, 2);

    const postCount = 13;
    final timelineAds = timelineAdSlotCount(postCount);
    expect(timelineAds, 2);
    final slotIndices = <int>[
      for (var index = 0; index < timelineAds; index++)
        homeTimelineAdSlotStart + index,
    ];
    expect(slotIndices, <int>[2, 3]);
    expect(slotIndices.toSet().length, slotIndices.length);
  });

  test('all posts stay in their original order for short and long feeds', () {
    for (final postCount in <int>[0, 1, 2, 3, 7, 9, 21, 100, 101, 1000]) {
      for (final postsPerAd in <int>[2, 5, 13]) {
        final posts = <int>[];
        final adCount = timelineAdSlotCount(postCount, postsPerAd: postsPerAd);
        var renderedAdCount = 0;
        for (var i = 0; i < postCount + adCount; i++) {
          if (isTimelineAdItem(i, postCount, postsPerAd: postsPerAd)) {
            renderedAdCount++;
          } else {
            posts.add(
              timelinePostIndexForItem(i, postCount, postsPerAd: postsPerAd),
            );
          }
        }
        expect(
          renderedAdCount,
          adCount,
          reason: 'postCount=$postCount postsPerAd=$postsPerAd',
        );
        expect(
          posts,
          List<int>.generate(postCount, (i) => i),
          reason: 'postCount=$postCount postsPerAd=$postsPerAd',
        );
      }
    }
  });

  test('invalid intervals insert no advertisements', () {
    expect(timelineAdSlotCount(10, postsPerAd: 0), 0);
    expect(timelineAdSlotCount(10, postsPerAd: -1), 0);
    expect(isTimelineAdItem(0, 10, postsPerAd: 0), false);
    expect(timelinePostIndexForItem(4, 10, postsPerAd: 0), 4);
  });
}
