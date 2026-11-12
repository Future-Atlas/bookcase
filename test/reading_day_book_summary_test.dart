import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/reading_session.dart';
import 'package:sharemarium/utils/reading_day_book_summary.dart';

ReadingSession reading(
  String id,
  String bookId,
  DateTime start,
  DateTime end,
) => ReadingSession(
  id: id,
  profileId: 'user',
  bookId: bookId,
  bookTitle: bookId,
  bookCoverUrl: '',
  startedAt: start,
  endedAt: end,
);

void main() {
  test('daily list sums sessions of the same book but not different books', () {
    final day = DateTime(2026, 11, 13);
    final one = reading('a', 'book-1', DateTime(2026, 11, 13, 9),
        DateTime(2026, 11, 13, 9, 20));
    final two = reading('b', 'book-1', DateTime(2026, 11, 13, 19),
        DateTime(2026, 11, 13, 19, 40));
    final other = reading('c', 'book-2', DateTime(2026, 11, 13, 21),
        DateTime(2026, 11, 13, 21, 15));
    final result = summarizeReadingDayBooks([one, two, other], day);
    expect(result.length, 2);
    expect(result[0].session.id, one.id);
    expect(result[0].total, const Duration(hours: 1));
    expect(result[1].total, const Duration(minutes: 15));
    // Per-session time ranges remain available in the unchanged records.
    expect(one.startedAt.hour, 9);
    expect(two.startedAt.hour, 19);
  });

  test('overnight sessions contribute only the time on the displayed day', () {
    final session = reading('overnight', 'book',
        DateTime(2026, 11, 12, 23, 45),
        DateTime(2026, 11, 13, 0, 15));
    final result = summarizeReadingDayBooks([session], DateTime(2026, 11, 13));
    expect(result.single.total, const Duration(minutes: 15));
  });
}
