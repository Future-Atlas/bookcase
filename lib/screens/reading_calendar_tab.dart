import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/reading_calendar_border.dart';
import '../utils/reading_calendar_month.dart';
import '../utils/reading_day_book_summary.dart';

import '../models/reading_session.dart';
import '../models/social_models.dart';
import '../models/user_profile.dart';
import 'post_engagement_users_screen.dart';
import '../widgets/reading_cover_art.dart';
import '../services/reading_session_service.dart';
import '../widgets/book_detail_dialog_frame.dart';

class ReadingCalendarTab extends StatefulWidget {
  const ReadingCalendarTab({
    super.key,
    required this.accentColor,
    required this.ownerId,
    required this.onProfileTap,
    this.onResume,
  });

  final Color accentColor;
  final String ownerId;
  final ValueChanged<UserProfile> onProfileTap;
  final Future<void> Function(ReadingSession session)? onResume;

  @override
  State<ReadingCalendarTab> createState() => _ReadingCalendarTabState();
}

class _ReadingCalendarTabState extends State<ReadingCalendarTab> {
  final ReadingSessionService _service = ReadingSessionService();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<ReadingSession> _sessions = [];
  ReadingSession? _active;
  Map<String, ReadingReactionSummary> _reactions = {};
  bool _canView = false;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReadingCalendarTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final canView = await _service.canViewCalendar(widget.ownerId);
      final sessions = canView
          ? await _service.loadMonth(_month, profileId: widget.ownerId)
          : <ReadingSession>[];
      final reactions = canView
          ? await _service.reactionSummaries(sessions)
          : <String, ReadingReactionSummary>{};
      final active = canView && widget.onResume != null
          ? await _service.activeSession()
          : null;
      if (!mounted || generation != _generation) return;
      setState(() {
        _canView = canView;
        _sessions = sessions;
        _active = active;
        _reactions = reactions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = '読書記録を読み込めませんでした。';
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
    _load();
  }

  List<ReadingSession> _sessionsFor(DateTime day) {
    return _sessions
        .where(
          (session) =>
              session.endedAt != null &&
              session.durationOnDay(day) > Duration.zero,
        )
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  }

  Duration _totalFor(DateTime day) {
    return _sessionsFor(
      day,
    ).fold(Duration.zero, (sum, session) => sum + session.durationOnDay(day));
  }

  Widget _roundCover(ReadingSession session, {double size = 52}) {
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: ColoredBox(
          color: Colors.black12,
          child: Padding(
            padding: EdgeInsets.all(size * 0.15),
            child: ReadingCoverArt(url: session.bookCoverUrl),
          ),
        ),
      ),
    );
  }

  Future<void> _showReactionUsers(
    ReadingSession session,
    PostReactionType reaction,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PostEngagementUsersScreen(
          readingSessionId: session.id,
          reaction: reaction,
          title: 'このリアクションをしたユーザー',
          onProfileTap: widget.onProfileTap,
        ),
      ),
    );
  }

  Widget _reactionButtons(
    ReadingSession session, {
    required StateSetter refreshDialog,
  }) {
    final summary = _reactions[session.id] ?? const ReadingReactionSummary();
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final reaction in PostReactionType.values)
          InkWell(
            key: ValueKey(
              'reading-reaction-${session.id}-${reaction.databaseValue}',
            ),
            borderRadius: BorderRadius.circular(18),
            onLongPress: () => _showReactionUsers(session, reaction),
            onSecondaryTap: () => _showReactionUsers(session, reaction),
            onTap: widget.onResume != null
                ? null
                : () async {
                    try {
                      await _service.toggleReaction(
                        session.id,
                        reaction,
                        summary.selected,
                      );
                      final next = await _service.reactionSummaries([session]);
                      if (!mounted) return;
                      refreshDialog(() {
                        _reactions = {..._reactions, ...next};
                      });
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('リアクションを保存できませんでした。')),
                      );
                    }
                  },
            child: Container(
              constraints: const BoxConstraints(minWidth: 42, minHeight: 34),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(
                color: summary.selected == reaction
                    ? const Color(0xFFD00303).withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: summary.selected == reaction
                      ? const Color(0xFFD00303)
                      : Colors.grey,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction.symbol, style: const TextStyle(fontSize: 17)),
                  if ((summary.counts[reaction] ?? 0) > 0) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${summary.counts[reaction]}',
                      style: const TextStyle(color: Colors.black, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showDay(DateTime day) async {
    final entries = _sessionsFor(day);
    final begin = DateTime(day.year, day.month, day.day);
    final next = DateTime(day.year, day.month, day.day + 1);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => BookDetailDialogFrame(
          child: SizedBox(
            width: math.min(MediaQuery.sizeOf(dialogContext).width - 70, 650),
            height: math.min(
              MediaQuery.sizeOf(dialogContext).height * 0.77,
              600,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${day.year}年${day.month}月${day.day}日の読書記録',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(child: Text('この日の読書記録はありません。'))
                        : ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 24),
                            itemBuilder: (context, index) {
                              final session = entries[index];
                              final start = session.startedAt.isBefore(begin)
                                  ? begin
                                  : session.startedAt;
                              final end = session.endedAt!.isAfter(next)
                                  ? next
                                  : session.endedAt!;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Column(
                                      children: [
                                        _roundCover(session, size: 66),
                                        const SizedBox(height: 4),
                                        Text(
                                          session.bookTitle,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${ReadingSession.timeLabel(start)}～'
                                          '${ReadingSession.timeLabel(end)}'
                                          '（${ReadingSession.durationLabel(session.durationOnDay(day))}）',
                                          style: const TextStyle(
                                            color: Colors.black,
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        _reactionButtons(
                                          session,
                                          refreshDialog: refreshDialog,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Reuse the monthly list's circular book artwork at a smaller size.
  /// A busy day uses a +N overflow badge instead of clipping into another date.
  Widget _dayBookBadges(
    List<ReadingDayBookSummary> books,
    BoxConstraints bounds,
  ) {
    if (books.isEmpty || bounds.maxWidth <= 0 || bounds.maxHeight <= 0) {
      return const SizedBox.shrink();
    }

    const gap = 1.0;
    var side = math.min(20.0, math.min(bounds.maxWidth, bounds.maxHeight));

    int capacity(double iconSide) {
      if (iconSide <= 0) return 0;
      final columns = ((bounds.maxWidth + gap) / (iconSide + gap)).floor();
      final rows = ((bounds.maxHeight + gap) / (iconSide + gap)).floor();
      return math.max(0, columns) * math.max(0, rows);
    }

    while (side > 8 && capacity(side) < books.length) {
      side -= 1;
    }
    final slots = capacity(side);
    if (slots <= 0) return const SizedBox.shrink();
    final visibleCount = books.length > slots
        ? math.max(0, slots - 1)
        : books.length;
    final remaining = books.length - visibleCount;

    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final book in books.take(visibleCount))
            Tooltip(
              message: book.session.bookTitle,
              child: KeyedSubtree(
                key: ValueKey('reading-calendar-book-${book.session.bookId}'),
                child: _roundCover(book.session, size: side),
              ),
            ),
          if (remaining > 0)
            SizedBox.square(
              dimension: side,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('+$remaining', style: const TextStyle(fontSize: 10)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(int index, int leading, int daysInMonth) {
    final number = index - leading + 1;
    if (number < 1 || number > daysInMonth) {
      return const SizedBox.shrink();
    }
    final day = DateTime(_month.year, _month.month, number);
    // The same book is only represented once regardless of session count.
    final books = summarizeReadingDayBooks(_sessionsFor(day), day);
    final today = DateTime.now();
    final isToday =
        day.year == today.year &&
        day.month == today.month &&
        day.day == today.day;
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        key: ValueKey('reading-calendar-day-$number'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showDay(day),
        child: Container(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              readingCalendarDayBorder(
                brightness: Theme.of(context).brightness,
                isToday: isToday,
                isDesktop: MediaQuery.sizeOf(context).width >= 768,
                accentColor: widget.accentColor,
              ),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$number', style: const TextStyle(fontSize: 12, height: 1)),
                if (books.isNotEmpty)
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) => _dayBookBadges(books, bounds),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final weekday = sundayFirstCalendarOffset(_month);
    final count = ((weekday + daysInMonth + 6) ~/ 7) * 7;
    final active = _active;
    final daysWithReading = List.generate(
      daysInMonth,
      (index) => DateTime(_month.year, _month.month, index + 1),
    ).where((day) => _sessionsFor(day).isNotEmpty).toList().reversed;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          if (active != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.timer, color: widget.accentColor),
                title: Text('計測中：${active.bookTitle}'),
                subtitle: const Text('タップして読書タイマーに戻る'),
                onTap: () async {
                  await widget.onResume?.call(active);
                  if (mounted) _load();
                },
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: '前の月',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                '${_month.year}年${_month.month}月',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              IconButton(
                tooltip: '次の月',
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(_error!),
            )
          else if (!_canView)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('読書カレンダーは承認されたフォロワーのみに公開されています。')),
            )
          else ...[
            Row(
              children: [
                for (final label in ['日', '月', '火', '水', '木', '金', '土'])
                  Expanded(child: Center(child: Text(label))),
              ],
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: count,
              itemBuilder: (context, index) =>
                  _dayCell(index, weekday, daysInMonth),
            ),
            const SizedBox(height: 20),
            Text(
              '※ 過去の記録を追加・編集することはできません。',
              key: const ValueKey('reading-calendar-no-history-edit-note'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'この月の読書記録',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'この月の合計読書時間：'
                  '${ReadingSession.durationLabel(totalReadingDurationInMonth(_sessions, _month))}',
                  key: const ValueKey('reading-calendar-month-total'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: widget.accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (daysWithReading.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('まだ読書記録はありません。右下の＋から計測できます。'),
              ),
            for (final day in daysWithReading)
              Card(
                child: InkWell(
                  onTap: () => _showDay(day),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${day.month}月${day.day}日',
                          style: TextStyle(
                            color: widget.accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (final summary in summarizeReadingDayBooks(
                          _sessionsFor(day), day,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 74,
                                  child: Column(
                                    children: [
                                      _roundCover(summary.session),
                                      const SizedBox(height: 3),
                                      Text(
                                        summary.session.bookTitle,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      ReadingSession.durationLabel(
                                        summary.total,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          '合計 ${ReadingSession.durationLabel(_totalFor(day))}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
