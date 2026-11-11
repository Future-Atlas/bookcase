import 'package:flutter_test/flutter_test.dart';
import 'package:sharemarium/models/reading_session.dart';

ReadingSession makeSession(DateTime startedAt, DateTime? endedAt) {
  return ReadingSession(
    id: 'session',
    profileId: 'profile',
    bookId: 'book',
    bookTitle: 'Example',
    bookCoverUrl: '',
    startedAt: startedAt,
    endedAt: endedAt,
  );
}

void main() {
  test('overnight reading is attributed to both calendar dates', () {
    final session = makeSession(
      DateTime(2026, 11, 10, 23, 45),
      DateTime(2026, 11, 11, 0, 15),
    );
    expect(
      session.durationOnDay(DateTime(2026, 11, 10)),
      const Duration(minutes: 15),
    );
    expect(
      session.durationOnDay(DateTime(2026, 11, 11)),
      const Duration(minutes: 15),
    );
    expect(
      session.durationOnDay(DateTime(2026, 11, 12)),
      Duration.zero,
    );
  });

  test('unfinished sessions do not appear as completed days', () {
    final session = makeSession(DateTime(2026, 11, 10, 9), null);
    expect(session.durationOnDay(DateTime(2026, 11, 10)), Duration.zero);
  });

  test('timer never displays more than 24 hours', () {
    final start = DateTime(2026, 11, 10, 9);
    final session = makeSession(start, null);
    expect(
      session.duration(now: start.add(const Duration(hours: 30))),
      const Duration(hours: 24),
    );
    expect(
      ReadingSession.durationLabel(const Duration(minutes: 135)),
      '2時間15分',
    );
  });
}
