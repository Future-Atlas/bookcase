import '../models/reading_session.dart';

/// Presentation-only grouping: the original reading sessions and timestamps
/// remain unchanged for the day detail and its per-session reactions.
class ReadingDayBookSummary {
  const ReadingDayBookSummary({
    required this.session,
    required this.total,
  });

  final ReadingSession session;
  final Duration total;
}

List<ReadingDayBookSummary> summarizeReadingDayBooks(
  Iterable<ReadingSession> sessions,
  DateTime day,
) {
  final representative = <String, ReadingSession>{};
  final totals = <String, Duration>{};
  for (final session in sessions) {
    final duration = session.durationOnDay(day);
    if (session.endedAt == null || duration <= Duration.zero) continue;
    // Book IDs are stable and distinguish distinct editions with the same
    // title; session IDs are deliberately not used here.
    final bookId = session.bookId;
    representative.putIfAbsent(bookId, () => session);
    totals[bookId] = (totals[bookId] ?? Duration.zero) + duration;
  }
  return [
    for (final entry in representative.entries)
      ReadingDayBookSummary(
        session: entry.value,
        total: totals[entry.key]!,
      ),
  ];
}
