import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/reading_session.dart';
import 'package:sharemarium/utils/reading_calendar_month.dart';

ReadingSession session(
  String id,
  String bookId,
  DateTime start,
  DateTime? end,
) => ReadingSession(
      id: id,
      profileId: 'reader',
      bookId: bookId,
      bookTitle: bookId,
      bookCoverUrl: '',
      startedAt: start,
      endedAt: end,
    );

void main() {
  test('Sunday is the first calendar column', () {
    expect(sundayFirstCalendarOffset(DateTime(2026, 11)), 0);
    expect(sundayFirstCalendarOffset(DateTime(2026, 6)), 1);
    expect(sundayFirstCalendarOffset(DateTime(2026, 12)), 2);
    expect(sundayFirstCalendarOffset(DateTime(2026, 8)), 6);
  });

  test('monthly total sums seconds before displaying truncated minutes', () {
    final records = [
      session('a', 'book-a', DateTime(2026, 11, 10, 8),
          DateTime(2026, 11, 10, 8, 0, 50)),
      session('b', 'book-a', DateTime(2026, 11, 10, 9),
          DateTime(2026, 11, 10, 9, 0, 30)),
      session('before', 'book-b', DateTime(2026, 10, 31, 23, 59, 30),
          DateTime(2026, 11, 1, 0, 0, 45)),
      session('after', 'book-c', DateTime(2026, 11, 30, 23, 59, 50),
          DateTime(2026, 12, 1, 0, 0, 30)),
      session('next', 'book-d', DateTime(2026, 12, 1, 10),
          DateTime(2026, 12, 1, 11)),
      session('active', 'book-e', DateTime(2026, 11, 20, 10), null),
    ];
    final total = totalReadingDurationInMonth(records, DateTime(2026, 11));
    expect(total.inSeconds, 135);
    expect(total.inMinutes, 2);
    // Session-level floor-to-minutes would lose both 50s and 30s records.
    expect(total.inMinutes, greaterThan(1));
  });

  test('month crossing clips each session to the selected month', () {
    final overnight = session(
      'overnight', 'book-a',
      DateTime(2026, 11, 30, 23, 59, 30),
      DateTime(2026, 12, 1, 0, 0, 30),
    );
    expect(totalReadingDurationInMonth([overnight], DateTime(2026, 11)),
        const Duration(seconds: 30));
    expect(totalReadingDurationInMonth([overnight], DateTime(2026, 12)),
        const Duration(seconds: 30));
  });
}
