import '../models/reading_session.dart';

/// DateTime.weekday is Monday = 1 ... Sunday = 7.
/// Rebase the first column to Sunday without changing calendar dates.
int sundayFirstCalendarOffset(DateTime month) =>
    DateTime(month.year, month.month, 1).weekday % 7;

/// Count only time falling inside the requested calendar month.
///
/// Sum full sub-minute durations before truncating the *monthly* result to
/// seconds. This avoids discarding a minute from every short session and
/// correctly splits readings that cross a month boundary.
Duration totalReadingDurationInMonth(
  Iterable<ReadingSession> sessions,
  DateTime month,
) {
  final monthStart = DateTime(month.year, month.month, 1);
  final nextMonth = DateTime(month.year, month.month + 1, 1);
  var accumulated = Duration.zero;

  for (final session in sessions) {
    final end = session.endedAt;
    if (end == null) continue;
    final from = session.startedAt.isAfter(monthStart)
        ? session.startedAt
        : monthStart;
    final until = end.isBefore(nextMonth) ? end : nextMonth;
    if (until.isAfter(from)) {
      accumulated += until.difference(from);
    }
  }

  return Duration(seconds: accumulated.inSeconds);
}
