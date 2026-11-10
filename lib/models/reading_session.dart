class ReadingSession {
  const ReadingSession({
    required this.id,
    required this.profileId,
    required this.bookId,
    required this.bookTitle,
    required this.bookCoverUrl,
    this.bookIsbn = '',
    this.bookCoverSource = '',
    required this.startedAt,
    this.endedAt,
  });

  final String id;
  final String profileId;
  final String bookId;
  final String bookTitle;
  final String bookCoverUrl;
  final String bookIsbn;
  final String bookCoverSource;
  final DateTime startedAt;
  final DateTime? endedAt;

  bool get isRunning => endedAt == null;

  factory ReadingSession.fromJson(Map<String, dynamic> data) {
    return ReadingSession(
      id: data['id'].toString(),
      profileId: data['profile_id'].toString(),
      bookId: data['book_id'].toString(),
      bookTitle: data['book_title'].toString(),
      bookCoverUrl: data['book_cover_url']?.toString() ?? '',
      bookIsbn: data['book_isbn']?.toString() ?? '',
      bookCoverSource: data['book_cover_source']?.toString() ?? '',
      startedAt: DateTime.parse(data['started_at'].toString()).toLocal(),
      endedAt: data['ended_at'] == null
          ? null
          : DateTime.parse(data['ended_at'].toString()).toLocal(),
    );
  }

  /// A single reading session is limited to 24 hours; never extrapolate
  /// beyond that limit even if the tab was suspended by the browser.
  Duration duration({DateTime? now}) {
    final end = endedAt ?? now ?? DateTime.now();
    final maximum = startedAt.add(const Duration(hours: 24));
    final effectiveEnd = end.isAfter(maximum) ? maximum : end;
    if (!effectiveEnd.isAfter(startedAt)) return Duration.zero;
    return effectiveEnd.difference(startedAt);
  }

  /// Allocate an overnight session to both dates, without allowing the
  /// user to manually choose a date or change the recorded timestamps.
  Duration durationOnDay(DateTime date) {
    if (endedAt == null) return Duration.zero;
    final dayStart = DateTime(date.year, date.month, date.day);
    final nextDay = DateTime(date.year, date.month, date.day + 1);
    final from = startedAt.isAfter(dayStart) ? startedAt : dayStart;
    final until = endedAt!.isBefore(nextDay) ? endedAt! : nextDay;
    return until.isAfter(from) ? until.difference(from) : Duration.zero;
  }

  static String durationLabel(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    return '${minutes ~/ 60}時間${minutes % 60}分';
  }

  static String timeLabel(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}時'
      '${time.minute.toString().padLeft(2, '0')}分';
}
